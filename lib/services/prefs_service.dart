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

  /// 回傳使用者是否已曾設定過路徑
  static Future<bool> hasRealmPath() async {
    final data = await _read();
    return data.containsKey('realm_path');
  }

  static Future<String> getRealmPath() async {
    final data = await _read();
    return (data['realm_path'] as String?) ?? kDefaultRealmPath;
  }

  static Future<void> setRealmPath(String path) async {
    final data = await _read();
    data['realm_path'] = path;
    await _write(data);
  }
}
