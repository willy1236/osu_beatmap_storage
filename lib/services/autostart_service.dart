import 'dart:io';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'prefs_service.dart';

/// 開機啟動時帶的參數；`main()` 看到就不開視窗、直接縮到系統匣
const autostartArg = '--autostart';

/// 寫入／移除登錄檔 `HKCU\...\Run` 的底層操作；測試時換成假的，不碰真實 registry
abstract class AutostartBackend {
  Future<bool> isEnabled();
  Future<void> enable();
  Future<void> disable();
}

/// 以 launch_at_startup 實作
class LaunchAtStartupBackend implements AutostartBackend {
  LaunchAtStartupBackend({String? exePath}) {
    launchAtStartup.setup(
      appName: 'osu_beatmap_storage',
      appPath: exePath ?? Platform.resolvedExecutable,
      args: const [autostartArg],
    );
  }

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();
  @override
  Future<void> enable() async => await launchAtStartup.enable();
  @override
  Future<void> disable() async => await launchAtStartup.disable();
}

/// 開機自動啟動開關。設定值存在 `config.json`，Run 項目由 [AutostartBackend] 維護。
class AutostartService {
  AutostartService({
    required AutostartBackend Function() backend,
    required Future<bool> Function() readEnabled,
    required Future<void> Function(bool) saveEnabled,
  }) : _backendFactory = backend,
       _readEnabled = readEnabled,
       _saveEnabled = saveEnabled;

  final AutostartBackend Function() _backendFactory;
  final Future<bool> Function() _readEnabled;
  final Future<void> Function(bool) _saveEnabled;
  AutostartBackend? _backend;

  AutostartBackend get _b => _backend ??= _backendFactory();

  static final AutostartService instance = AutostartService(
    backend: LaunchAtStartupBackend.new,
    readEnabled: PrefsService.getLaunchAtStartup,
    saveEnabled: PrefsService.setLaunchAtStartup,
  );

  Future<bool> isEnabled() => _readEnabled();

  /// 切換開關：先動 Run 項目，成功才存設定。失敗會丟例外，設定維持原值
  Future<void> setEnabled(bool value) async {
    if (value) {
      await _b.enable();
    } else {
      await _b.disable();
    }
    await _saveEnabled(value);
  }

  /// 啟動時呼叫：設定為開啟就重寫一次 Run 項目，搬移資料夾後路徑才會跟上。
  /// 設定為關閉時不碰 registry。失敗靜默略過
  Future<void> syncOnStart() async {
    try {
      if (!await _readEnabled()) return;
      await _b.enable();
    } catch (_) {}
  }
}
