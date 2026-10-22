import 'package:flutter/material.dart';

import '../app.dart' show appNavigatorKey;
import '../pages/cloud_list_page.dart';
import 'auth_service.dart';
import 'local_library_service.dart';
import 'shared_list_service.dart';

/// 「拿到分享 token 就開啟對方清單」的單一入口。
///
/// 所有來源（帳號選單貼上連結、之後的 URI scheme／單一執行個體轉交）都呼叫 [open]：
/// - 未登入：彈對話框提示並附登入鈕，token 暫存在記憶體，登入成功後自動開啟
/// - 已登入：讀本機 OnlineID 集合後開啟唯讀的 [CloudListPage]
///
/// 需要 [appNavigatorKey] 已掛在 `MaterialApp`；還沒掛上時 [open] 回 false。
class ShareLinkOpener {
  ShareLinkOpener({
    GlobalKey<NavigatorState>? navigatorKey,
    Listenable? authChanges,
    bool Function()? isLoggedIn,
    AuthStatus Function()? authStatus,
    Future<void> Function()? login,
    SharedListService? service,
    LocalLibraryService? library,
  }) : _navKey = navigatorKey ?? appNavigatorKey,
       _authChanges = authChanges ?? AuthService.instance,
       _isLoggedIn = isLoggedIn ?? (() => AuthService.instance.isLoggedIn),
       _authStatus = authStatus ?? (() => AuthService.instance.status),
       _login = login ?? (() => AuthService.instance.login()),
       _service = service ?? SharedListService.instance,
       _library = library ?? LocalLibraryService.instance;

  static final ShareLinkOpener instance = ShareLinkOpener();

  final GlobalKey<NavigatorState> _navKey;
  final Listenable _authChanges;
  final bool Function() _isLoggedIn;
  final AuthStatus Function() _authStatus;
  final Future<void> Function() _login;
  final SharedListService _service;
  final LocalLibraryService _library;

  String? _pending;
  bool _sawLoggingIn = false;
  bool _listening = false;
  bool _busy = false;

  /// 等待登入完成後開啟的 token（測試與除錯用）
  String? get pendingToken => _pending;

  /// 開啟 [token] 對應的分享清單。回傳 true 表示已處理（開了頁面、或已提示登入／本機未載入）；
  /// false 表示畫面還沒準備好（navigator 尚未掛上），呼叫端可稍後再試。
  Future<bool> open(String token) async {
    final overlay = _navKey.currentState?.overlay;
    if (overlay == null) return false;
    if (_busy) return true;
    _busy = true;
    try {
      if (!_isLoggedIn()) {
        await _promptLogin(overlay.context, token);
        return true;
      }
      _clearPending();
      var localIds = _library.onlineIds;
      if (localIds == null) {
        // 還沒讀到本機清單：全部會被標成「本機缺」，讓使用者決定要不要照開
        if (!await _confirmNoLocal(overlay.context)) return true;
        localIds = const {};
      }
      _navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => CloudListPage(
            title: '分享的清單',
            loader: () => _service.fetch(token),
            localIds: localIds!,
          ),
        ),
      );
      return true;
    } finally {
      _busy = false;
    }
  }

  Future<void> _promptLogin(BuildContext context, String token) async {
    _pending = token;
    _sawLoggingIn = false;
    _startListening();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要先登入'),
        content: const Text('開啟分享連結需要先登入析域帳號。登入完成後會自動開啟這份清單。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('登入'),
          ),
        ],
      ),
    );
    if (go == true) {
      // 不等待：登入結果由 [_onAuthChanged] 處理
      _login();
    } else {
      _clearPending();
    }
  }

  Future<bool> _confirmNoLocal(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('尚未載入本機圖譜'),
        content: const Text('還沒讀到本機的 client.realm，清單裡的圖譜會全部標示為「本機缺」。要繼續開啟嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('仍要開啟'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _startListening() {
    if (_listening) return;
    _listening = true;
    _authChanges.addListener(_onAuthChanged);
  }

  void _clearPending() {
    _pending = null;
    _sawLoggingIn = false;
    if (_listening) {
      _listening = false;
      _authChanges.removeListener(_onAuthChanged);
    }
  }

  void _onAuthChanged() {
    final token = _pending;
    if (token == null) return;
    if (_isLoggedIn()) {
      _clearPending();
      open(token);
      return;
    }
    switch (_authStatus()) {
      case AuthStatus.loggingIn:
        _sawLoggingIn = true;
      case AuthStatus.loggedOut || AuthStatus.reloginRequired:
        // 登入被取消或失敗：不再等待
        if (_sawLoggingIn) _clearPending();
      default:
        break;
    }
  }
}
