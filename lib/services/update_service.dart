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
      if (source == null) throw Exception('下載的檔案裡找不到 $_exeName');

      final script = File(p.join(work.path, 'apply_update.ps1'));
      await script.writeAsString(_applyScript);
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
        _error = '更新失敗：更新程式沒有啟動，請改為手動下載 zip 更新';
        _setStatus(UpdateStatus.failed, null);
        return;
      }
      exit(0);
    } catch (e) {
      _error = '更新失敗：$e';
      _setStatus(UpdateStatus.failed, null);
    }
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
    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout) {
      if (started.existsSync()) return true;
      await Future<void>.delayed(interval);
    }
    if (started.existsSync()) return true;
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

/// 等程式結束 → 舊程式檔移到 .update_backup → 複製新檔 → 重新啟動。
/// 舊程式逾時仍未結束就放棄更新（不換檔、不重啟）。換檔失敗會盡力回滾，
/// 錯誤寫進 update_error.log，且無論如何都會重新啟動程式。只動程式檔，不碰資料。
const _applyScript = r'''
param([int]$AppPid, [string]$Source, [string]$Target, [string]$Exe, [string]$Started, [int]$WaitSeconds = 60)
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $Started -Value 'started'
$log = Join-Path $Target 'update_error.log'

Wait-Process -Id $AppPid -Timeout $WaitSeconds -ErrorAction SilentlyContinue
if (Get-Process -Id $AppPid -ErrorAction SilentlyContinue) {
  try { "舊程式 (pid $AppPid) 在 $WaitSeconds 秒內沒有結束，已放棄更新" | Out-File -FilePath $log -Encoding utf8 } catch {}
  exit 1
}
Start-Sleep -Milliseconds 500

$backup = Join-Path $Target '.update_backup'
$moved = $false
$copying = $false
try {
  if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
  New-Item -ItemType Directory -Path $backup | Out-Null

  $old = @(Get-ChildItem -Path $Target -File -Filter '*.dll')
  foreach ($name in @($Exe, 'data')) {
    $path = Join-Path $Target $name
    if (Test-Path $path) { $old += Get-Item $path }
  }

  $moved = $true
  foreach ($item in $old) { Move-Item -Path $item.FullName -Destination $backup }
  $copying = $true
  Get-ChildItem -Path $Source | Copy-Item -Destination $Target -Recurse -Force
  Remove-Item $backup -Recurse -Force
} catch {
  try { $_ | Out-File -FilePath $log -Encoding utf8 } catch {}
  if ($moved) {
    # 盡力回滾：每一步失敗都繼續做下一步
    $ErrorActionPreference = 'Continue'
    if ($copying) {
      # 只有已開始複製才需要清掉新檔；否則同名檔就是還沒搬走的舊檔，不能刪
      foreach ($item in @(Get-ChildItem -Path $Source)) {
        $path = Join-Path $Target $item.Name
        if (Test-Path $path) { Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue }
      }
    }
    foreach ($item in @(Get-ChildItem -Path $backup)) {
      Move-Item -Path $item.FullName -Destination $Target -Force -ErrorAction Continue
    }
    if (-not @(Get-ChildItem -Path $backup -ErrorAction SilentlyContinue)) {
      Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

try {
  Start-Process -FilePath (Join-Path $Target $Exe) -WorkingDirectory $Target
} catch {
  try { $_ | Out-File -FilePath $log -Append -Encoding utf8 } catch {}
}
Remove-Item $Source -Recurse -Force -ErrorAction SilentlyContinue
''';
