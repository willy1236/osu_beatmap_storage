import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:realm/realm.dart';
import '../models/osu_realm_models.dart';
import 'prefs_service.dart';
import 'realm_service.dart';

/// 負責管理 danser-go 執行檔的下載、解壓縮與呼叫。
///
/// 啟動流程：呼叫 [ensureReady]，若 bin/danser.exe 不存在則自動
/// 從 GitHub Releases 下載最新版並解壓縮至 AppSupport/bin/。
class DanserService extends ChangeNotifier {
  static final instance = DanserService._();
  DanserService._();

  bool _ready = false;
  bool _checking = false;
  String _statusMessage = '';
  double? _progress; // null = 不確定進度
  String? _error;

  bool get isReady => _ready;
  bool get isChecking => _checking;
  String get statusMessage => _statusMessage;
  double? get progress => _progress;
  String? get error => _error;

  String? _danserExePath;

  /// danser.exe 的絕對路徑，僅在 [isReady] 為 true 後有效。
  String? get danserExePath => _danserExePath;

  static const _githubApiUrl =
      'https://api.github.com/repos/Wieku/danser-go/releases/latest';

  static String get _platformSuffix {
    if (Platform.isWindows) return 'win';
    if (Platform.isMacOS) return 'mac';
    return 'linux';
  }

  static String get _exeName =>
      Platform.isWindows ? 'danser-cli.exe' : 'danser-cli';

  Future<Directory> _getBinDir() async {
    final dir = Directory(p.join(Directory.current.path, 'bin'));
    await dir.create(recursive: true);
    return dir;
  }

  /// 確保 danser 執行檔存在，不存在則下載並解壓縮。
  /// 可安全地重複呼叫；若已就緒則立即返回。
  Future<void> ensureReady() async {
    if (_ready) return;
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();

    try {
      final binDir = await _getBinDir();
      final existing = _findExeInDir(binDir);
      if (existing != null) {
        _danserExePath = existing.path;
        // 每次啟動時同步 osu!lazer 路徑設定（realm 路徑可能已變更）
        await _configureDanserSettings();
        _ready = true;
        _checking = false;
        notifyListeners();
        return;
      }
      await _downloadAndInstall(binDir);
    } catch (e) {
      _error = e.toString();
      _checking = false;
      notifyListeners();
    }
  }

  /// 重置狀態並重新執行 [ensureReady]（供 UI 的「重試」按鈕使用）。
  Future<void> retrySetup() async {
    if (_checking) return;
    _ready = false;
    _error = null;
    await ensureReady();
  }

  Future<void> _downloadAndInstall(Directory binDir) async {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));

    // 1. 從 GitHub API 取得最新 release 資訊
    _setStatus('正在取得版本資訊...', null);
    late Map<String, dynamic> releaseData;
    try {
      final resp = await dio.get<Map<String, dynamic>>(
        _githubApiUrl,
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
      releaseData = resp.data!;
    } on DioException catch (e) {
      throw Exception('無法連線至 GitHub：${e.message}');
    }

    final tagName = releaseData['tag_name'] as String;
    final assets = (releaseData['assets'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    final suffix = _platformSuffix;
    final Map<String, dynamic> asset;
    try {
      asset = assets.firstWhere((a) {
        final name = a['name'] as String;
        return name.contains(suffix) && name.endsWith('.zip');
      });
    } catch (_) {
      throw Exception('在 GitHub 找不到 $suffix 平台的 danser-go 封裝檔');
    }

    final downloadUrl = asset['browser_download_url'] as String;
    final assetName = asset['name'] as String;

    // 2. 下載 zip
    final zipPath = p.join(binDir.path, assetName);
    _setStatus('正在下載 danser-go $tagName...', 0);
    try {
      await dio.download(
        downloadUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _setStatus('正在下載 danser-go $tagName...', received / total);
          }
        },
      );
    } on DioException catch (e) {
      // 確保殘留的暫存 zip 被清除
      try {
        final tmp = File(zipPath);
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {}
      throw Exception('下載失敗：${e.message}');
    }

    // 3. 驗證 zip 下載完整
    final zipFile = File(zipPath);
    if (!zipFile.existsSync() || zipFile.lengthSync() < 1024) {
      throw Exception('zip 下載不完整或檔案遺失（路徑：$zipPath）');
    }

    // 4. 在背景 Isolate 解壓縮，避免 UI 卡頓
    _setStatus('正在解壓縮...', null);
    final extractError = await compute(_extractZipIsolate, {
      'zipPath': zipPath,
      'binPath': binDir.path,
    });
    if (extractError != null) {
      throw Exception('解壓縮失敗：$extractError');
    }

    // 5. 找到解壓後的執行檔（相容根目錄或子目錄結構）
    final exeFile = _findExeInDir(binDir);
    if (exeFile == null) {
      throw Exception('解壓縮後找不到 $_exeName，請嘗試手動安裝至 ${binDir.path}');
    }

    // 6. 非 Windows 需要設定執行權限
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', exeFile.path]);
    }

    _danserExePath = exeFile.path;

    // 7. 寫入 osu!lazer 路徑設定，讓 danser 能找到圖譜與音源
    await _configureDanserSettings();

    _ready = true;
    _checking = false;
    _progress = null;
    _statusMessage = '';
    notifyListeners();
  }

  File? _findExeInDir(Directory dir) {
    if (!dir.existsSync()) return null;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path) == _exeName) {
        return entity;
      }
    }
    return null;
  }

  void _setStatus(String message, double? progress) {
    _statusMessage = message;
    _progress = progress;
    notifyListeners();
  }

  /// 依目前的 client.realm 路徑，自動更新 danser 的 settings/default.json。
  ///
  /// danser-go 透過 [General.OsuSongsDir] 找到 osu!lazer 的 hash‑based
  /// 檔案庫（即 client.realm 同層的 files/ 目錄），才能取得圖譜音訊與背景。
  /// 此方法為 best-effort：失敗時只記錄警告，不中斷整體流程。
  Future<void> _configureDanserSettings() async {
    if (_danserExePath == null) return;
    try {
      final lazerDir = await PrefsService.getOsuDir();

      // danser 以執行檔所在目錄為工作目錄，settings 路徑相對於此
      final danserDir = p.dirname(_danserExePath!);
      final settingsDir = Directory(p.join(danserDir, 'settings'));
      await settingsDir.create(recursive: true);
      final settingsFile = File(p.join(settingsDir.path, 'default.json'));

      // 讀取現有設定（保留使用者自訂項目）
      Map<String, dynamic> settings = {};
      if (settingsFile.existsSync()) {
        try {
          final raw = await settingsFile.readAsString();
          settings = (jsonDecode(raw) as Map<String, dynamic>?) ?? {};
        } catch (_) {}
      }

      // 僅更新 osu!lazer 相關路徑，其餘保持不變
      final general = Map<String, dynamic>.from(
        (settings['General'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      // osu!lazer 根目錄（包含 client.realm 的那層）
      // danser-go 會自動在此目錄下尋找 client.realm，
      // 並透過 <OsuSongsDir>/files/<hash> 讀取圖譜資源。
      // 注意：不可指向 files/ 子目錄，否則 danser 找不到 client.realm。
      final lazerDirFwd = lazerDir.replaceAll('\\', '/');
      general['OsuSongsDir'] = lazerDirFwd;
      general['OsuSkinsDir'] = '$lazerDirFwd/skins';
      settings['General'] = general;

      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings),
        flush: true,
      );
    } catch (_) {
      // 設定寫入失敗不影響主流程，使用者可手動設定
    }
  }

  /// 當使用者變更 client.realm 路徑後，呼叫此方法同步 danser 設定。
  Future<void> updateLazerSettings() => _configureDanserSettings();

  /// 以絕對路徑啟動 danser-go。
  ///
  /// 工作目錄自動設為 danser 執行檔所在資料夾，使 danser
  /// 能正確載入相鄰的設定檔（songs.cfg 等）。
  Future<Process> launch(List<String> args) async {
    if (_danserExePath == null) {
      throw StateError('danser 尚未就緒，請先呼叫 ensureReady()');
    }
    return Process.start(
      _danserExePath!,
      args,
      workingDirectory: p.dirname(_danserExePath!),
    );
  }

  /// 使用 danser-go 將 .osr 回放渲染為 .mp4。
  ///
  /// 流程：
  ///   1. 解析 .osr 取得 beatmap MD5
  ///   2. 從 client.realm 找到對應的 BeatmapSet 並取出所有檔案
  ///   3. 複製檔案至臨時目錄，重建「虛擬 stable」Songs 結構
  ///   4. 暫時覆寫 default.json，將 OsuSongsDir 指向臨時目錄
  ///   5. 執行 danser 渲染（不傳 -settings 旗標，避免 danser 誤判參數）
  ///   6. finally：還原 default.json、清理臨時目錄
  ///
  /// Yields 進度值 0.0–1.0；stream 正常關閉代表成功，失敗時拋出例外。
  Stream<double> renderReplay(String osrPath, String outputPath) async* {
    if (_danserExePath == null) {
      throw StateError('danser 尚未就緒，請先呼叫 ensureReady()');
    }
    // danser 的 -out 參數只接受「純檔名」（不含路徑、不含副檔名）
    // 輸出目錄則透過 Recording.OutputDir 寫入 default.json
    final outputNoExt = outputPath.endsWith('.mp4')
        ? outputPath.substring(0, outputPath.length - 4)
        : outputPath;
    final outputDir = p.dirname(outputNoExt);
    final outputStem = p.basename(outputNoExt);

    // 確保輸出目錄存在
    await Directory(outputDir).create(recursive: true);

    // 1. 建立虛擬 stable 譜曲目錄環境
    final env = await _prepareDanserEnvironment(osrPath);

    // 讀取 skin 設定
    final danserDir = p.dirname(_danserExePath!);
    final osuDir = await PrefsService.getOsuDir();

    // 解析 skin 設定：優先使用從 Realm 選擇的 skin，否則回退到手動設定
    String? resolvedSkinName;
    String? resolvedSkinsDir;

    final skinRealmId = await PrefsService.getSkinRealmId();
    if (skinRealmId.isNotEmpty) {
      final result = await _ensureSkinReady(skinRealmId, osuDir, danserDir);
      resolvedSkinName = result.$1;
      resolvedSkinsDir = result.$2;
    } else {
      final manualName = await PrefsService.getSkinName();
      final manualDir = await PrefsService.getSkinsDir();
      if (manualName.isNotEmpty) {
        resolvedSkinName = manualName;
        resolvedSkinsDir = manualDir.isEmpty ? null : manualDir;
      }
    }

    final defaultJsonFile = File(p.join(danserDir, 'settings', 'default.json'));
    List<int>? originalJsonBytes;

    try {
      // 2. 備份現有 default.json，覆寫為指向臨時 Songs 目錄的設定
      if (defaultJsonFile.existsSync()) {
        originalJsonBytes = await defaultJsonFile.readAsBytes();
      }
      await _patchDefaultSettings(
        defaultJsonFile,
        env.songsDir.path,
        outputDir,
        skinName: resolvedSkinName,
        skinsDir: resolvedSkinsDir,
      );

      // 3. 啟動 danser（-out 只傳純檔名，輸出目錄由 Recording.OutputDir 控制）
      final process = await Process.start(_danserExePath!, [
        '-replay',
        osrPath,
        '-out',
        outputStem,
        '-record',
      ], workingDirectory: danserDir);

      // danser-go 將進度同時寫入 stdout 與 stderr
      // 合併兩個 stream 一起解析，避免任一端緩衝區滿造成死鎖
      // allLines 同時收集 stdout + stderr，用於錯誤診斷
      final allLines = <String>[];

      // 解析進度的正則：匹配 "21.72%" 或 "1234/5678 (21.72%)" 等格式
      final progressRe = RegExp(r'(\d+(?:\.\d+)?)\s*%');

      // 用 StreamController 合併 stdout + stderr
      final combined = StreamController<String>();
      int pending = 2;
      void closeMaybe() {
        pending--;
        if (pending == 0) combined.close();
      }

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              allLines.add(line);
              combined.add(line);
            },
            onDone: closeMaybe,
            cancelOnError: false,
          );

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              allLines.add(line);
              combined.add(line);
            },
            onDone: closeMaybe,
            cancelOnError: false,
          );

      await for (final line in combined.stream) {
        final match = progressRe.firstMatch(line);
        if (match != null) {
          final pct = double.tryParse(match.group(1)!);
          if (pct != null) yield (pct / 100.0).clamp(0.0, 1.0);
        }
      }

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw Exception('danser 結束碼 $exitCode\n${allLines.join('\n').trim()}');
      }
    } finally {
      // 還原 default.json（無論成功或失敗都必須執行）
      try {
        if (originalJsonBytes != null) {
          await defaultJsonFile.writeAsBytes(originalJsonBytes, flush: true);
        }
      } catch (_) {}
      // 清理臨時目錄（忽略錯誤，避免 Windows 檔案鎖定問題）
      try {
        await env.tempRoot.delete(recursive: true);
      } catch (_) {}
    }
  }

  // ── OSR 解析 ─────────────────────────────────────────────────────────────────

  /// 解析 .osr 二進位格式，提取 beatmap MD5 hash。
  /// OSR 格式：mode[1] + version[4] + beatmapMD5[leb128_string] + ...
  static String _parseOsrBeatmapMd5(String osrPath) {
    final bytes = File(osrPath).readAsBytesSync();
    if (bytes.length < 6) {
      throw FormatException('OSR 檔案過短，無法解析 (path: $osrPath)');
    }
    return _readOsrString(bytes, 5).$1; // 跳過 mode(1) + version(4)
  }

  /// 從指定 offset 讀取一個 ULEB128 字串，回傳 (value, newOffset)。
  static (String, int) _readOsrString(Uint8List bytes, int offset) {
    if (offset >= bytes.length) throw RangeError('OSR 資料不足');
    final marker = bytes[offset++];
    if (marker == 0x00) return ('', offset);
    if (marker != 0x0b) {
      throw FormatException('非法字串標記 0x${marker.toRadixString(16)}，OSR 格式可能有誤');
    }
    // 解碼 ULEB128 長度
    int length = 0;
    int shift = 0;
    while (true) {
      if (offset >= bytes.length) {
        throw RangeError('ULEB128 解碼超出 OSR 資料範圍');
      }
      final b = bytes[offset++];
      length |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    if (offset + length > bytes.length) {
      throw RangeError('OSR 字串資料長度超出範圍');
    }
    final str = utf8.decode(bytes.sublist(offset, offset + length));
    return (str, offset + length);
  }

  // ── 虛擬 stable 環境準備 ──────────────────────────────────────────────────────

  /// 從 osu!lazer client.realm 查詢對應 MD5 的譜面集，
  /// 將所有相關檔案復原原始檔名並複製至臨時目錄。
  /// 回傳 ({songsDir, tempRoot})：songsDir 指向 Songs/ 層，tempRoot 是創建的根目錄。
  Future<({Directory songsDir, Directory tempRoot})> _prepareDanserEnvironment(
    String osrPath,
  ) async {
    final md5 = _parseOsrBeatmapMd5(osrPath);
    final osuDir = await PrefsService.getOsuDir();
    final realmPath = p.join(osuDir, 'client.realm');

    final realm = await RealmService.openWithFiles(realmPath);
    try {
      // 找到含有此 MD5 的 BeatmapSet
      BeatmapSetInfo? targetSet;
      outer:
      for (final set in realm.all<BeatmapSetInfo>()) {
        for (final beat in set.beatmaps) {
          if (beat.md5Hash == md5) {
            targetSet = set;
            break outer;
          }
        }
      }

      if (targetSet == null) {
        throw Exception('在 Realm 中找不到 MD5 為 $md5 的譜面，請確認該譜面已匯入 osu!lazer');
      }

      // 建立臨時目錄結構：
      //   tempRoot/Songs/{onlineID} beatmap/
      // 子目錄使用 osu! stable 命名慣例（數字 ID + 空格 + 名稱）
      final tempRoot = await Directory.systemTemp.createTemp('danser_replay_');
      final setDir = '${targetSet.onlineID} beatmap';
      final beatmapDir = Directory(p.join(tempRoot.path, 'Songs', setDir));
      await beatmapDir.create(recursive: true);

      // 從 osu!lazer hash-based 路徑複製檔案，重命名為原始檔名
      final filesRoot = p.join(osuDir, 'files');
      int copiedCount = 0;
      final missingHashes = <String>[];

      for (final fileUsage in targetSet.files) {
        final hash = fileUsage.file?.hash;
        if (hash == null || hash.length < 2) continue;

        // osu!lazer 的 hash-based 路徑：files/a/ab/abcdef...
        final srcPath = p.join(
          filesRoot,
          hash.substring(0, 1),
          hash.substring(0, 2),
          hash,
        );
        final srcFile = File(srcPath);
        if (!srcFile.existsSync()) {
          missingHashes.add(hash.substring(0, 8));
          continue;
        }

        final filename = fileUsage.filename;
        if (filename == null) continue;
        final dstPath = p.join(beatmapDir.path, filename);
        // 建立必要的子目錄（filename 可能含有路徑分隔符）
        await Directory(p.dirname(dstPath)).create(recursive: true);
        await srcFile.copy(dstPath);
        copiedCount++;
      }

      if (copiedCount == 0) {
        await tempRoot.delete(recursive: true);
        final missingInfo = missingHashes.isNotEmpty
            ? '（找不到的 hash：${missingHashes.join(', ')}...）'
            : '';
        throw Exception(
          '譜面集 ${targetSet.onlineID} 的檔案列表為空'
          '（Files 關聯筆數: ${targetSet.files.length}）$missingInfo。\n'
          '可能原因：譜面尚未完成下載，或 Realm Files 映射有誤。',
        );
      }

      final songsDir = Directory(p.join(tempRoot.path, 'Songs'));
      return (songsDir: songsDir, tempRoot: tempRoot);
    } finally {
      realm.close();
    }
  }

  /// 確保指定的 Realm skin 已複製到 danser 的 Skins 資料夾。
  ///
  /// 邏輯：
  ///   1. 查詢 client.realm 找到對應 SkinInfo
  ///   2. 若 danserDir/Skins/{skinName}/skin.ini 已存在 → 直接沿用
  ///   3. 否則從 osuDir/files/ hash-based 路徑複製所有 skin 檔案
  ///
  /// 回傳 (skinFolderName, skinsFolderPath) 供寫入 default.json 使用。
  Future<(String, String)> _ensureSkinReady(
    String skinRealmId,
    String osuDir,
    String danserDir,
  ) async {
    final realmPath = p.join(osuDir, 'client.realm');
    final realm = await RealmService.openWithSkins(realmPath);

    try {
      final uuid = Uuid.fromString(skinRealmId);
      final skinInfo = realm.find<SkinInfo>(uuid);
      if (skinInfo == null) {
        throw Exception('找不到 skin（ID: $skinRealmId），請重新選擇');
      }

      final skinName = (skinInfo.name ?? '').isNotEmpty
          ? skinInfo.name!
          : skinRealmId.substring(0, 8);
      final danserSkinsDir = p.join(danserDir, 'Skins');
      final skinDir = Directory(p.join(danserSkinsDir, skinName));

      // 若 skin.ini 已存在，不需要重新複製
      if (File(p.join(skinDir.path, 'skin.ini')).existsSync()) {
        return (skinName, danserSkinsDir);
      }

      // 從 osu!lazer hash-based 路徑複製 skin 檔案
      await skinDir.create(recursive: true);
      final filesRoot = p.join(osuDir, 'files');

      for (final fileUsage in skinInfo.files) {
        final hash = fileUsage.file?.hash;
        if (hash == null || hash.length < 2) continue;

        final srcPath = p.join(
          filesRoot,
          hash.substring(0, 1),
          hash.substring(0, 2),
          hash,
        );
        final srcFile = File(srcPath);
        if (!srcFile.existsSync()) continue;

        final filename = fileUsage.filename;
        if (filename == null) continue;
        final dstPath = p.join(skinDir.path, filename);
        await Directory(p.dirname(dstPath)).create(recursive: true);
        await srcFile.copy(dstPath);
      }

      return (skinName, danserSkinsDir);
    } finally {
      realm.close();
    }
  }

  /// 暫時修改 [defaultJsonFile] 的 OsuSongsDir，指向臨時 Songs 目錄。
  /// 呼叫者須在 finally 中自行還原備份。
  Future<void> _patchDefaultSettings(
    File defaultJsonFile,
    String songsDirPath,
    String outputDirPath, {
    String? skinName,
    String? skinsDir,
  }) async {
    Map<String, dynamic> base = {};
    if (defaultJsonFile.existsSync()) {
      try {
        base =
            (jsonDecode(await defaultJsonFile.readAsString())
                as Map<String, dynamic>?) ??
            {};
      } catch (_) {}
    }

    // 只修改必要欄位；保留其餘使用者設定（解析度、skin、音量等）
    final general = Map<String, dynamic>.from(
      (base['General'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    general['OsuSongsDir'] = songsDirPath.replaceAll('\\', '/');
    base['General'] = general;

    // 設定輸出目錄（danser 將 -out 檔名附加到此目錄）
    final recording = Map<String, dynamic>.from(
      (base['Recording'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    recording['OutputDir'] = outputDirPath.replaceAll('\\', '/');
    base['Recording'] = recording;

    // 套用 skin（若有指定）
    // danser 使用 General.OsuSkinsDir 決定 skin 搜尋路徑，而非 Skin 區塊
    if (skinsDir != null) {
      general['OsuSkinsDir'] = skinsDir.replaceAll('\\', '/');
    }
    if (skinName != null) {
      final skin = Map<String, dynamic>.from(
        (base['Skin'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      skin['CurrentSkin'] = skinName;
      base['Skin'] = skin;
    }

    // 停用癲癇警告（SeizureWarning 在 Playfield 區塊內）
    final playfield = Map<String, dynamic>.from(
      (base['Playfield'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    final seizureWarning = Map<String, dynamic>.from(
      (playfield['SeizureWarning'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    seizureWarning['Enabled'] = false;
    playfield['SeizureWarning'] = seizureWarning;
    base['Playfield'] = playfield;

    await defaultJsonFile.parent.create(recursive: true);
    await defaultJsonFile.writeAsString(
      const JsonEncoder.withIndent('\t').convert(base),
      flush: true,
    );
  }
}

/// 頂層函式：供 [compute()] 在獨立 Isolate 中執行解壓縮。
/// 回傳 null 表示成功，回傳錯誤訊息字串表示失敗。
/// 參數使用 Map<String,String> 確保跨 Isolate 序列化相容性。
String? _extractZipIsolate(Map<String, String> args) {
  try {
    final zipPath = args['zipPath']!;
    final binPath = args['binPath']!;
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      // 防止路徑穿越攻擊（Path Traversal）
      final entryName = entry.name.replaceAll('\\', '/');
      if (entryName.contains('..')) continue;
      final outPath = p.join(binPath, p.joinAll(entryName.split('/')));
      if (entry.isFile) {
        final outFile = File(outPath);
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(entry.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
    // 清理 zip
    File(zipPath).deleteSync();
    return null;
  } catch (e) {
    return e.toString();
  }
}
