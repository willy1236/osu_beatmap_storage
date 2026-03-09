import 'dart:convert';
import 'dart:io';
import '../constants.dart';

/// 持久化儲存使用者偏好設定
/// 資料寫入執行目錄下的 config.json，方便管理與備份
abstract final class PrefsService {
  static const _fileName = 'config.json';

  static File get _file =>
      File('${Directory.current.path}${Platform.pathSeparator}$_fileName');

  static Future<Map<String, dynamic>> _read() async {
    try {
      if (!_file.existsSync()) return {};
      final content = await _file.readAsString();
      return (jsonDecode(content) as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  /// 回傳使用者是否已曾設定過 osu 目錄
  static Future<bool> hasOsuDir() async {
    final data = await _read();
    return data.containsKey('osu_dir');
  }

  static Future<String> getOsuDir() async {
    final data = await _read();
    return (data['osu_dir'] as String?) ?? kDefaultOsuDir;
  }

  static Future<void> setOsuDir(String dir) async {
    final data = await _read();
    data['osu_dir'] = dir;
    await _write(data);
  }

  /// danser 渲染時使用的 skin 名稱（對應 danser Skins/ 下的資料夾名稱）
  /// 空字串 = 使用 danser 目前設定（不修改）
  static Future<String> getSkinName() async {
    final data = await _read();
    return (data['skin_name'] as String?) ?? '';
  }

  static Future<void> setSkinName(String name) async {
    final data = await _read();
    data['skin_name'] = name;
    await _write(data);
  }

  /// 自訂 Skins 資料夾路徑（例如指向 osu!stable 的 Skins 資料夾）
  /// 空字串 = 使用 danser 頑目下的 Skins/ 資料夾
  static Future<String> getSkinsDir() async {
    final data = await _read();
    return (data['skins_dir'] as String?) ?? '';
  }

  static Future<void> setSkinsDir(String dir) async {
    final data = await _read();
    data['skins_dir'] = dir;
    await _write(data);
  }

  /// 使用者從 osu!lazer Realm 選擇的 skin UUID
  /// 空字串 = 不使用 Realm skin（回覆手動設定）
  static Future<String> getSkinRealmId() async {
    final data = await _read();
    return (data['skin_realm_id'] as String?) ?? '';
  }

  static Future<void> setSkinRealmId(String id) async {
    final data = await _read();
    data['skin_realm_id'] = id;
    await _write(data);
  }
}
