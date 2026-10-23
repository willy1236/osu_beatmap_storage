import 'dart:io';
import 'package:path/path.dart' as p;

/// 首次啟動時自動尋找 osu!lazer 資料夾（包含 client.realm 的那層）：
/// 1. `%APPDATA%\osu\storage.ini` 的 `FullPath`（在 lazer 裡搬過資料夾時才有）
/// 2. 預設位置 `%APPDATA%\osu`
/// 兩者都沒有 client.realm 時回 null，由呼叫端改讓使用者手動選取
class OsuDirDetector {
  /// [appData] 預設讀環境變數 APPDATA；測試時傳入暫存資料夾
  static Future<String?> detect({String? appData}) async {
    final base = appData ?? Platform.environment['APPDATA'];
    if (base == null || base.isEmpty) return null;
    final defaultDir = p.join(base, 'osu');

    final custom = await _readStorageIni(p.join(defaultDir, 'storage.ini'));
    for (final dir in [?custom, defaultDir]) {
      if (await File(p.join(dir, 'client.realm')).exists()) return dir;
    }
    return null;
  }

  static Future<String?> _readStorageIni(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      for (final line in await file.readAsLines()) {
        final i = line.indexOf('=');
        if (i < 0 || line.substring(0, i).trim() != 'FullPath') continue;
        final value = line.substring(i + 1).trim();
        return value.isEmpty ? null : value;
      }
    } catch (_) {
      // 讀不到或編碼錯誤：當作沒有自訂位置
    }
    return null;
  }
}
