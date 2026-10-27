import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' show WindowsException;
import 'package:win32_registry/win32_registry.dart';

/// Inno Setup 寫入的解除安裝項目；GUID 與 `installer/setup.iss` 的 AppId 相同
const _uninstallKey =
    r'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8C00BB22-9985-4B24-A4A4-B90B111005CE}_is1';

/// 解除安裝項目的讀寫；測試時換成假的，不碰真實 registry
abstract class InstallRegistry {
  String? read(String name);
  void write(String name, String value);
}

class _WinInstallRegistry implements InstallRegistry {
  _WinInstallRegistry._();

  /// 沒有用安裝檔裝過（免安裝版）就回 null
  static InstallRegistry? open() {
    try {
      Registry.openPath(RegistryHive.currentUser, path: _uninstallKey).close();
      return _WinInstallRegistry._();
    } on WindowsException {
      return null;
    }
  }

  @override
  String? read(String name) {
    final key = Registry.openPath(
      RegistryHive.currentUser,
      path: _uninstallKey,
    );
    try {
      return key.getStringValue(name);
    } finally {
      key.close();
    }
  }

  @override
  void write(String name, String value) {
    final key = Registry.openPath(
      RegistryHive.currentUser,
      path: _uninstallKey,
      desiredAccessRights: AccessRights.allAccess,
    );
    try {
      key.createValue(RegistryValue.string(name, value));
    } finally {
      key.close();
    }
  }
}

/// 讓「程式和功能」顯示的版本跟上程式內更新或手動覆蓋 zip 後的實際版本。
class InstalledVersionService {
  InstalledVersionService({
    required InstallRegistry? Function() open,
    required String version,
    required String exeDir,
  }) : _open = open,
       _version = version,
       _exeDir = exeDir;

  final InstallRegistry? Function() _open;
  final String _version;
  final String _exeDir;

  static final InstalledVersionService instance = InstalledVersionService(
    open: _WinInstallRegistry.open,
    version: const String.fromEnvironment('APP_VERSION'),
    exeDir: p.dirname(Platform.resolvedExecutable),
  );

  /// 啟動時呼叫：只有解除安裝項目指向目前這個資料夾才改，另外放的免安裝版不會動到安裝版的紀錄。
  /// 本機開發沒帶版本時不動作。失敗靜默略過
  void syncOnStart() {
    try {
      if (_version.isEmpty) return;
      final reg = _openHere();
      if (reg == null) return;
      if (reg.read('DisplayVersion') == _version) return;
      reg.write('DisplayVersion', _version);
    } catch (_) {}
  }

  /// 目前這個資料夾是否由安裝檔裝的；是的話程式內更新改跑安裝檔。讀不到 registry 視為否
  bool isInstalledHere() {
    try {
      return _openHere() != null;
    } catch (_) {
      return false;
    }
  }

  InstallRegistry? _openHere() {
    final reg = _open();
    if (reg == null) return null;
    final location = reg.read('InstallLocation');
    if (location == null || !p.windows.equals(location, _exeDir)) return null;
    return reg;
  }
}
