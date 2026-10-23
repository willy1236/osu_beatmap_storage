import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'prefs_service.dart';

/// 關閉視窗時的行為，存在 `config.json` 的 `close_action`
enum CloseAction {
  ask,
  tray,
  exit;

  static CloseAction parse(String? v) =>
      CloseAction.values.firstWhere((a) => a.name == v, orElse: () => ask);
}

/// 詢問對話框的結果：選了什麼、要不要記住。使用者按叉或取消時回 null（代表不關閉）
typedef CloseChoice = ({CloseAction action, bool remember});

/// 視窗與系統匣的底層操作；[TrayService] 只透過它們做事，測試時換成假的
abstract class TrayPlatform {
  /// 開始接收「使用者要關視窗」與「點系統匣圖示」「選匣選單的結束」三種事件
  Future<void> init({
    required VoidCallback onCloseRequested,
    required VoidCallback onTrayIconClick,
    required VoidCallback onQuitSelected,
  });
  Future<void> hideWindow();
  Future<void> showWindow();

  /// 結束程式（會真的關掉視窗，不再詢問）
  Future<void> destroyWindow();
  Future<void> showTrayIcon();
  Future<void> removeTrayIcon();
}

/// 縮到系統匣的邏輯。對外只有「隱藏到系統匣」「還原」「結束」，
/// 與關閉視窗時依設定處理的 [handleCloseRequested]。
class TrayService {
  TrayService({
    required TrayPlatform platform,
    required Future<CloseAction> Function() readCloseAction,
    required Future<void> Function(CloseAction) saveCloseAction,
    required Future<CloseChoice?> Function() askCloseAction,
  }) : _platform = platform,
       _readCloseAction = readCloseAction,
       _saveCloseAction = saveCloseAction,
       _askCloseAction = askCloseAction;

  final TrayPlatform _platform;
  final Future<CloseAction> Function() _readCloseAction;
  final Future<void> Function(CloseAction) _saveCloseAction;
  final Future<CloseChoice?> Function() _askCloseAction;

  bool _inTray = false;
  bool _handling = false;

  /// 目前視窗是否收在系統匣
  bool get inTray => _inTray;

  static final TrayService instance = TrayService(
    platform: WindowTrayPlatform(),
    readCloseAction: () async =>
        CloseAction.parse(await PrefsService.getCloseAction()),
    saveCloseAction: (a) => PrefsService.setCloseAction(a.name),
    // 對話框由 main.dart 啟動後注入（需要 navigator），見 [askHook]
    askCloseAction: () async => askHook?.call(),
  );

  /// 詢問對話框的實作，由 app 層設定，避免 service 依賴 UI
  static Future<CloseChoice?> Function()? askHook;

  Future<void> init() => _platform.init(
    onCloseRequested: () => handleCloseRequested(),
    onTrayIconClick: () => restore(),
    onQuitSelected: () => quit(),
  );

  /// 程式啟動時初始化系統匣；[minimized] 為 true（開機自動啟動）時縮到系統匣。
  /// 任何一步失敗都只記 log，不丟例外。縮到系統匣沒成功時，原生視窗在自動啟動下尚未
  /// 顯示（見 flutter_window.cpp），沒人叫出就會在背景跑卻沒有視窗也沒有系統匣圖示，
  /// 所以失敗時盡力把視窗顯示出來
  Future<void> start({required bool minimized}) async {
    try {
      await init();
      if (minimized) await hideToTray();
    } catch (e) {
      debugPrint('系統匣初始化失敗：$e');
      if (!minimized) return;
      try {
        await _platform.removeTrayIcon();
      } catch (_) {}
      try {
        await _platform.showWindow();
        _inTray = false;
      } catch (e2) {
        debugPrint('顯示視窗失敗：$e2');
      }
    }
  }

  /// 使用者按了視窗的關閉鈕。設定為 ask 時跳對話框，取消則什麼都不做
  Future<void> handleCloseRequested() async {
    if (_handling) return;
    _handling = true;
    try {
      var action = await _readCloseAction();
      if (action == CloseAction.ask) {
        final choice = await _askCloseAction();
        if (choice == null) return;
        action = choice.action;
        if (choice.remember) await _saveCloseAction(action);
      }
      if (action == CloseAction.tray) {
        await hideToTray();
      } else {
        await quit();
      }
    } finally {
      _handling = false;
    }
  }

  Future<void> hideToTray() async {
    await _platform.showTrayIcon();
    await _platform.hideWindow();
    _inTray = true;
  }

  Future<void> restore() async {
    await _platform.showWindow();
    await _platform.removeTrayIcon();
    _inTray = false;
  }

  Future<void> quit() async {
    await _platform.removeTrayIcon();
    await _platform.destroyWindow();
  }
}

/// 以 window_manager 與 tray_manager 實作的 [TrayPlatform]
class WindowTrayPlatform
    with WindowListener, TrayListener
    implements TrayPlatform {
  static const _iconAsset = 'windows/runner/resources/app_icon.ico';
  static const _quitKey = 'quit';

  VoidCallback? _onClose;
  VoidCallback? _onTrayClick;
  VoidCallback? _onQuit;

  @override
  Future<void> init({
    required VoidCallback onCloseRequested,
    required VoidCallback onTrayIconClick,
    required VoidCallback onQuitSelected,
  }) async {
    _onClose = onCloseRequested;
    _onTrayClick = onTrayIconClick;
    _onQuit = onQuitSelected;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
  }

  @override
  Future<void> hideWindow() => windowManager.hide();

  @override
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> destroyWindow() => windowManager.destroy();

  @override
  Future<void> showTrayIcon() async {
    await trayManager.setIcon(_iconAsset);
    await trayManager.setToolTip('osu! Beatmap Viewer');
    await trayManager.setContextMenu(
      Menu(
        items: [MenuItem(key: _quitKey, label: '結束')],
      ),
    );
  }

  @override
  Future<void> removeTrayIcon() => trayManager.destroy();

  @override
  void onWindowClose() => _onClose?.call();

  @override
  void onTrayIconMouseDown() => _onTrayClick?.call();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == _quitKey) _onQuit?.call();
  }
}
