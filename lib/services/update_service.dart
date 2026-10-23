import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// GitHub 上最新一版的資訊
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.zipUrl,
  });

  /// 不含前綴 v，例如 `2.2.0`
  final String version;
  final String notes;
  final String zipUrl;
}

/// 更新流程中可直接顯示給使用者的錯誤
class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum UpdateStatus { idle, available, downloading, installing, failed }

/// 檢查 GitHub Releases 有沒有新版，並原地更新程式。
///
/// 資料（config.json、osu_downloads/、bin/ 等）與程式放在同一資料夾，所以更新時
/// 只替換程式檔：執行檔、`*.dll` 與 `data/`。程式執行中檔案被鎖住，替換交給
/// 一支 PowerShell 腳本，等本程式結束後再搬檔、重新啟動。
///
/// 目前版本由建置時的 `--dart-define=APP_VERSION=x.y.z` 帶入；沒帶（本機開發）就不檢查。
class UpdateService extends ChangeNotifier {
  static final instance = UpdateService();

  UpdateService({http.Client? client, String? currentVersion, bool? isWindows})
    : _client = client ?? http.Client(),
      currentVersion =
          currentVersion ?? const String.fromEnvironment('APP_VERSION'),
      _isWindows = isWindows ?? Platform.isWindows;

  static const _latestUrl =
      'https://api.github.com/repos/willy1236/osu_beatmap_storage/releases/latest';
  static const _assetPrefix = 'osu_beatmap_storage';
  static const _exeName = 'osu_beatmap_storage.exe';

  final http.Client _client;
  final bool _isWindows;

  /// 空字串表示本機開發版
  final String currentVersion;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateInfo? _available;
  double? _progress;
  String? _error;

  UpdateStatus get status => _status;

  /// 有比目前新的版本時才非 null
  UpdateInfo? get available => _available;

  /// 下載進度 0–1；null 表示不確定
  double? get progress => _progress;
  String? get error => _error;

  /// 查詢最新版。失敗只記錄、不丟例外，不影響程式使用。
  Future<void> check() async {
    if (!_isWindows || currentVersion.isEmpty) return;
    try {
      final resp = await _client.get(
        Uri.parse(_latestUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final version = (data['tag_name'] as String).replaceFirst(
        RegExp('^v'),
        '',
      );
      if (!isNewer(version, currentVersion)) return;
      final asset = (data['assets'] as List).cast<Map<String, dynamic>>().where(
        (a) {
          final name = a['name'] as String;
          return name.startsWith(_assetPrefix) && name.endsWith('.zip');
        },
      ).firstOrNull;
      if (asset == null) return;
      _available = UpdateInfo(
        version: version,
        notes: (data['body'] as String?) ?? '',
        zipUrl: asset['browser_download_url'] as String,
      );
      _status = UpdateStatus.available;
      notifyListeners();
    } catch (e) {
      debugPrint('檢查更新失敗：$e');
    }
  }

  /// 下載並解壓新版，交給腳本替換程式檔後結束本程式。失敗時回到可重試狀態。
  Future<void> install() async {
    final info = _available;
    if (info == null ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing) {
      return;
    }
    _error = null;
    _setStatus(UpdateStatus.downloading, 0);
    try {
      final work = Directory(
        p.join(Directory.systemTemp.path, 'osu_beatmap_storage_update'),
      );
      if (work.existsSync()) await work.delete(recursive: true);
      await work.create(recursive: true);

      final zipPath = p.join(work.path, 'update.zip');
      await Dio().download(
        info.zipUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) _setStatus(UpdateStatus.downloading, received / total);
        },
      );

      _setStatus(UpdateStatus.installing, null);
      final extractDir = p.join(work.path, 'files');
      await compute(_extract, (zip: zipPath, out: extractDir));
      final source = _findAppRoot(Directory(extractDir));
      if (source == null) throw UpdateException('下載的檔案裡找不到 $_exeName');

      final script = File(p.join(work.path, 'apply_update.ps1'));
      await script.writeAsBytes([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(_applyScript),
      ]);
      final started = File(p.join(work.path, 'started.flag'));
      final ok = await launchApplyScript(
        start: () => Process.start(
          'powershell',
          applyScriptArgs(
            script: script.path,
            appPid: pid,
            source: source.path,
            target: p.dirname(Platform.resolvedExecutable),
            exe: _exeName,
            started: started.path,
          ),
          // 不能用 detached：GUI 程式以 DETACHED_PROCESS 啟動 powershell，
          // 腳本完全不會執行。normal 模式不開主控台視窗，子程序在本程式結束後仍會存活。
        ),
        started: started,
      );
      if (!ok) {
        throw const UpdateException(launchFailedMessage);
      }
      exit(0);
    } catch (e) {
      _error = describeError(e);
      _setStatus(UpdateStatus.failed, null);
    }
  }

  static const launchFailedMessage = '更新程式沒有啟動，請改為手動下載 zip 更新';

  /// 轉成給使用者看的失敗訊息，拿掉 `Exception: ` 之類的前綴
  @visibleForTesting
  static String describeError(Object e) {
    var text = e.toString().replaceFirst(
      RegExp(r'^\w*Exception(\s*\[[^\]]*\])?: '),
      '',
    );
    if (e is DioException) {
      text = e.message?.isNotEmpty == true ? e.message! : '網路連線失敗';
    }
    return '更新失敗：$text';
  }

  @visibleForTesting
  static const applyScriptSource = _applyScript;

  /// 組出啟動 [_applyScript] 的 powershell 參數。參數以 list 傳給 Process.start，
  /// 由 Dart 負責 CreateProcess 的 quoting，不經 cmd，所以路徑含空格、`%`、`&` 都安全。
  @visibleForTesting
  static List<String> applyScriptArgs({
    required String script,
    required int appPid,
    required String source,
    required String target,
    required String exe,
    required String started,
    int waitSeconds = 60,
  }) => [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    script,
    '-AppPid',
    '$appPid',
    '-Source',
    source,
    '-Target',
    target,
    '-Exe',
    exe,
    '-Started',
    started,
    '-WaitSeconds',
    '$waitSeconds',
  ];

  /// 啟動腳本並等它寫出 [started] 標記，確認真的跑起來才回傳 true。
  /// 逾時或啟動丟例外回傳 false（逾時會嘗試終止已啟動的程序）。
  @visibleForTesting
  static Future<bool> launchApplyScript({
    required Future<Process> Function() start,
    required File started,
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    Process? proc;
    try {
      proc = await start();
    } catch (e) {
      debugPrint('啟動更新腳本失敗：$e');
      return false;
    }
    var exited = false;
    unawaited(proc.exitCode.then((_) => exited = true));
    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout) {
      if (started.existsSync()) return true;
      // 腳本在寫出標記前就結束（例如無法檢查舊程式而放棄），不必等到逾時
      if (exited) return started.existsSync();
      await Future<void>.delayed(interval);
    }
    if (started.existsSync()) return true;
    // 殺不掉時，用 cancel 標記要求腳本在換檔前放棄
    try {
      File('${started.path}.cancel').writeAsStringSync('cancel');
    } catch (_) {}
    if (!proc.kill()) debugPrint('逾時後無法終止更新腳本程序 (pid ${proc.pid})');
    return false;
  }

  void _setStatus(UpdateStatus status, double? progress) {
    _status = status;
    _progress = progress;
    notifyListeners();
  }

  /// [latest] 是否比 [current] 新；只比較 `x.y.z` 的數字部分，無法解析視為不新
  @visibleForTesting
  static bool isNewer(String latest, String current) {
    List<int>? parse(String v) {
      final parts = v.split('+').first.split('-').first.split('.');
      final nums = parts.map(int.tryParse).toList();
      if (nums.any((n) => n == null)) return null;
      return [...nums.cast<int>(), 0, 0, 0].take(3).toList();
    }

    final a = parse(latest), b = parse(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// zip 可能直接放檔案，也可能多包一層資料夾；找出含執行檔的那層
  static Directory? _findAppRoot(Directory dir) {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path) == _exeName) {
        return entity.parent;
      }
    }
    return null;
  }
}

void _extract(({String zip, String out}) args) {
  final archive = ZipDecoder().decodeBytes(File(args.zip).readAsBytesSync());
  for (final entry in archive) {
    final name = entry.name.replaceAll('\\', '/');
    if (name.split('/').contains('..')) continue;
    final outPath = p.join(args.out, p.joinAll(name.split('/')));
    if (entry.isFile) {
      File(outPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(entry.content as List<int>);
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }
}

/// 更新腳本（內容必須維持純 ASCII，避免 Windows PowerShell 5.1 以 ANSI 碼頁誤解碼）。
///
/// 流程：先鎖定舊程式再寫 started 標記 → 等舊程式結束（逾時或被 cancel 就放棄）→
/// 新程式檔（exe、頂層 *.dll、data/）先完整複製到 .update_staging（失敗時 Target 不變）→
/// 舊程式檔 rename 到 .update_backup、新的 rename 進來，失敗時只做 rename 回滾 →
/// 其他項目合併複製（不刪 Target 內容，失敗只記 log）→ 重新啟動。
/// 殘留的舊備份改名保留、不還原不刪除。
/// 錯誤寫進 update_error.log。
const _applyScript = r'''
param([int]$AppPid, [string]$Source, [string]$Target, [string]$Exe, [string]$Started, [int]$WaitSeconds = 60)
$ErrorActionPreference = 'Stop'
$log = Join-Path $Target 'update_error.log'
Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
$cancel = $Started + '.cancel'

function Write-Log([string]$Message) {
  try { Add-Content -LiteralPath $log -Value $Message -Encoding UTF8 } catch {}
}

# Run an action up to 5 times (200 ms apart); log and return $false if it keeps failing.
function Invoke-Retry([scriptblock]$Action, [string]$What) {
  $err = $null
  for ($i = 0; $i -lt 5; $i++) {
    try { & $Action; return $true } catch { $err = $_; Start-Sleep -Milliseconds 200 }
  }
  Write-Log "FAILED: $What : $err"
  return $false
}

# .NET based helpers: no wildcard globbing, so paths containing [ ] are safe.
function Move-Entry([string]$From, [string]$To) {
  if ([IO.Directory]::Exists($From)) { [IO.Directory]::Move($From, $To) } else { [IO.File]::Move($From, $To) }
}
# Merge copy: directories are merged recursively, files overwrite; nothing in the destination is deleted.
function Copy-Entry([string]$From, [string]$To) {
  if ([IO.Directory]::Exists($From)) {
    [void][IO.Directory]::CreateDirectory($To)
    foreach ($child in [IO.Directory]::GetFileSystemEntries($From)) {
      Copy-Entry $child (Join-Path $To ([IO.Path]::GetFileName($child)))
    }
  } else {
    [IO.File]::Copy($From, $To, $true)
  }
}

# Program items: the exe, data/ and top-level *.dll (exact extension). Only these are
# staged, swapped as a whole and rolled back. Everything else in Source is merge-copied.
function Test-Program([string]$Name) {
  return ($Name -ieq $Exe) -or ($Name -ieq 'data') -or ([IO.Path]::GetExtension($Name) -ieq '.dll')
}

function Abort-Update([string]$Message) {
  Write-Log $Message
  Remove-Item -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}

# Take a handle on the old app BEFORE announcing that we started, so a reused PID is never
# mistaken for it. If the app is running but cannot be inspected, do not touch any file.
$proc = $null
try { $proc = Get-Process -Id $AppPid -ErrorAction Stop } catch { $proc = $null }
if ($proc) {
  try { [void]$proc.Handle } catch {
    if (Get-Process -Id $AppPid -ErrorAction SilentlyContinue) {
      Abort-Update "Cannot inspect the old app (pid $AppPid); update aborted without changes."
    }
    $proc = $null
  }
}

Set-Content -LiteralPath $Started -Value 'started'

if ($proc) {
  $exited = $false
  try {
    $exited = $proc.WaitForExit($WaitSeconds * 1000)
  } catch {
    $exited = -not (Get-Process -Id $AppPid -ErrorAction SilentlyContinue)
  }
  if (-not $exited) {
    Abort-Update "Old app (pid $AppPid) did not exit within $WaitSeconds s; update aborted."
  }
}
Start-Sleep -Milliseconds 500

# The app gave up waiting for us (and could not kill us): the old app is still running.
if (Test-Path -LiteralPath $cancel) {
  Remove-Item -LiteralPath $cancel -Force -ErrorAction SilentlyContinue
  Abort-Update 'Update cancelled by the app; no changes made.'
}

# Never delete or restore a backup left by an earlier run; just move it aside and keep it.
$backup = Join-Path $Target '.update_backup'
if (Test-Path -LiteralPath $backup) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $aside = Join-Path $Target ".update_backup_$stamp"
  if (Invoke-Retry { Move-Entry $backup $aside } 'move old .update_backup aside') {
    Write-Log "Kept a leftover backup from an earlier update as $aside (not restored)."
  } else {
    $backup = Join-Path $Target ('.update_backup_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Write-Log "Could not move the leftover .update_backup aside; using $backup for this update."
  }
}

# A leftover staging folder only holds partial copies of new files: delete it, else use another name.
$staging = Join-Path $Target '.update_staging'
if (Test-Path -LiteralPath $staging) {
  if (-not (Invoke-Retry { Remove-Item -LiteralPath $staging -Recurse -Force } 'delete old .update_staging')) {
    $staging = Join-Path $Target ('.update_staging_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  }
}

$newNames = New-Object System.Collections.ArrayList
$moved = New-Object System.Collections.ArrayList
$placed = New-Object System.Collections.ArrayList
$ok = $false
$staged = $true
try {
  # Phase 1: copy the complete new program files into staging. Target is untouched here.
  [void][IO.Directory]::CreateDirectory($staging)
  foreach ($e in [IO.Directory]::GetFileSystemEntries($Source)) {
    $name = [IO.Path]::GetFileName($e)
    if (Test-Program $name) {
      Copy-Entry $e (Join-Path $staging $name)
      [void]$newNames.Add($name)
    }
  }
} catch {
  Write-Log "Copy to staging failed; Target left unchanged: $_"
  $staged = $false
}

if ($staged) {
  try {
    # Phase 2: swap by rename. Old program files go to the backup, new ones come from staging.
    [void][IO.Directory]::CreateDirectory($backup)
    $oldNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in [IO.Directory]::GetFiles($Target)) {
      $n = [IO.Path]::GetFileName($e)
      if ([IO.Path]::GetExtension($n) -ieq '.dll') { [void]$oldNames.Add($n) }
    }
    [void]$oldNames.Add($Exe)
    [void]$oldNames.Add('data')
    foreach ($name in $oldNames) {
      if (Test-Path -LiteralPath (Join-Path $Target $name)) {
        $from = Join-Path $Target $name
        $to = Join-Path $backup $name
        if (-not (Invoke-Retry { Move-Entry $from $to } "back up $name")) { throw "cannot back up $name" }
        [void]$moved.Add($name)
      }
    }
    foreach ($name in $newNames) {
      $from = Join-Path $staging $name
      $to = Join-Path $Target $name
      if (-not (Invoke-Retry { Move-Entry $from $to } "place $name")) { throw "cannot place $name" }
      [void]$placed.Add($name)
    }
    $ok = $true
  } catch {
    Write-Log "Swap failed, rolling back: $_"
    try {
      for ($i = $placed.Count - 1; $i -ge 0; $i--) {
        $name = $placed[$i]
        $from = Join-Path $Target $name
        $to = Join-Path $staging $name
        [void](Invoke-Retry { Move-Entry $from $to } "move new $name back to staging")
      }
      foreach ($name in $moved) {
        $from = Join-Path $backup $name
        $to = Join-Path $Target $name
        [void](Invoke-Retry { Move-Entry $from $to } "restore $name")
      }
      if (-not @(Get-ChildItem -LiteralPath $backup -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
      }
    } catch {
      Write-Log "Rollback error: $_"
    }
  }
}

if ($ok) {
  # Other items: merge copy. A failure here is only logged; the new program files stay.
  try {
    foreach ($e in [IO.Directory]::GetFileSystemEntries($Source)) {
      $name = [IO.Path]::GetFileName($e)
      if (-not (Test-Program $name)) {
        $dest = Join-Path $Target $name
        [void](Invoke-Retry { Copy-Entry $e $dest } "merge $name")
      }
    }
  } catch { Write-Log "Merge error: $_" }
  # Cleanup must never undo the update; failures are only logged.
  [void](Invoke-Retry { Remove-Item -LiteralPath $backup -Recurse -Force } 'clean up backup')
}
Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue

try {
  # Not Start-Process: its -FilePath is globbed, which breaks paths containing [ ].
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = Join-Path $Target $Exe
  $psi.WorkingDirectory = $Target
  $psi.UseShellExecute = $true
  [void][System.Diagnostics.Process]::Start($psi)
} catch {
  Write-Log "Restart failed: $_"
}
Remove-Item -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue
''';
