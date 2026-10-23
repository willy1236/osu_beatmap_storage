import 'package:flutter/material.dart';

import '../app.dart' show appNavigatorKey;
import 'auth_service.dart';
import 'friend_service.dart';
import 'invite_link_service.dart';

/// 「拿到好友邀請 token 就確認並加好友」的單一入口，登入提示流程同 `ShareLinkOpener`。
///
/// 所有來源（URI scheme、單一執行個體轉交、貼上連結）都呼叫 [open]：
/// - 未登入：彈對話框提示並附登入鈕，token 暫存在記憶體，登入成功後自動繼續
/// - 已登入：先 `preview` 取得擁有者，自己的連結、已是好友直接提示；
///   否則問「要和 X 成為好友嗎」，確認後才 `accept`（取消不會消耗連結）
///
/// 需要 [appNavigatorKey] 已掛在 `MaterialApp`；還沒掛上時 [open] 回 false。
class FriendLinkOpener {
  FriendLinkOpener({
    GlobalKey<NavigatorState>? navigatorKey,
    Listenable? authChanges,
    bool Function()? isLoggedIn,
    AuthStatus Function()? authStatus,
    Future<void> Function()? login,
    InviteLinkService? service,
    String? Function()? selfId,
    FriendRelation Function(String accountId)? relationOf,
  }) : _navKey = navigatorKey ?? appNavigatorKey,
       _authChanges = authChanges ?? AuthService.instance,
       _isLoggedIn = isLoggedIn ?? (() => AuthService.instance.isLoggedIn),
       _authStatus = authStatus ?? (() => AuthService.instance.status),
       _login = login ?? (() => AuthService.instance.login()),
       _service = service ?? InviteLinkService.instance,
       _selfId = selfId ?? (() => AuthService.instance.sub),
       _relationOf =
           relationOf ?? ((id) => FriendService.instance.relationOf(id));

  static final FriendLinkOpener instance = FriendLinkOpener();

  final GlobalKey<NavigatorState> _navKey;
  final Listenable _authChanges;
  final bool Function() _isLoggedIn;
  final AuthStatus Function() _authStatus;
  final Future<void> Function() _login;
  final InviteLinkService _service;
  final String? Function() _selfId;
  final FriendRelation Function(String accountId) _relationOf;

  String? _pending;
  bool _sawLoggingIn = false;
  bool _listening = false;
  bool _busy = false;

  /// 等待登入完成後處理的 token（測試與除錯用）
  String? get pendingToken => _pending;

  /// 處理 [token]。回傳 true 表示已處理（含已提示登入、已顯示結果）；
  /// false 表示畫面還沒準備好（navigator 尚未掛上），呼叫端可稍後再試。
  Future<bool> open(String token) async {
    final overlay = _navKey.currentState?.overlay;
    if (overlay == null) return false;
    if (_busy) return true;
    _busy = true;
    try {
      final context = overlay.context;
      if (!_isLoggedIn()) {
        await _promptLogin(context, token);
        return true;
      }
      _clearPending();
      final preview = await _service.preview(token);
      if (!context.mounted) return true;
      final owner = preview.owner;
      if (owner == null) {
        await _notice(context, preview.message ?? '邀請連結已失效');
        return true;
      }
      final self = _selfId();
      if (self != null && self.toLowerCase() == owner.accountId.toLowerCase()) {
        await _notice(context, '這是你自己的邀請連結，請傳給朋友使用');
        return true;
      }
      if (_relationOf(owner.accountId) == FriendRelation.friends) {
        await _notice(context, '你和 ${owner.displayName} 已經是好友');
        return true;
      }
      if (!await _confirm(context, owner.displayName)) return true;
      if (!context.mounted) return true;
      final r = await _service.accept(token);
      if (!context.mounted) return true;
      // 被擁有者封鎖時後端回應像成功，這裡也一樣顯示成功
      await _notice(
        context,
        r.ok ? '你和 ${owner.displayName} 已成為好友' : (r.message ?? '操作失敗'),
      );
      return true;
    } finally {
      _busy = false;
    }
  }

  Future<void> _notice(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('好友邀請連結'),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好'),
            ),
          ],
        ),
      );

  Future<bool> _confirm(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('好友邀請連結'),
        content: Text('要和 $name 成為好友嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('成為好友'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _promptLogin(BuildContext context, String token) async {
    _pending = token;
    _sawLoggingIn = false;
    _startListening();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要先登入'),
        content: const Text('使用好友邀請連結需要先登入析域帳號。登入完成後會自動繼續加好友。'),
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
