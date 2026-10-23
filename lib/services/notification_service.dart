import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'friend_service.dart';
import 'push_service.dart';
import 'realtime_service.dart';
import 'toast_platform.dart';
import 'tray_service.dart';

/// 點通知後要切到的畫面
enum NotificationTarget {
  /// 好友頁的「收到的邀請」區
  invites,

  /// 好友頁，並開啟收件匣
  inbox,
}

/// 好友邀請與推送的紅點與 Windows 通知。
///
/// - 訂閱 [RealtimeService] 的 `friend_request`、`friend_added`、`push`：先重讀列表，
///   再用重讀前後的差集決定要通知哪幾筆，所以不依賴事件的內容
/// - 只有即時事件會發通知；登入與重連時的整份重讀（[FriendService]、[PushService] 自己做）
///   只更新列表與紅點，不發通知
/// - 列表尚未讀到時收到事件，只重讀不發通知（沒有基準可比）
/// - 紅點數量由 [badgeCount] 從兩個列表推導，處理完邀請或標已讀後自然消失
/// - 點通知：還原視窗，再透過 [intent] 要求 UI 切到對應畫面（UI 處理完後設回 null）
class NotificationService extends ChangeNotifier {
  NotificationService({
    AuthService? auth,
    RealtimeService? realtime,
    FriendService? friends,
    PushService? push,
    ToastPlatform? toast,
    Future<void> Function()? restoreWindow,
  }) : _auth = auth ?? AuthService.instance,
       _realtime = realtime ?? RealtimeService.instance,
       _friends = friends ?? FriendService.instance,
       _push = push ?? PushService.instance,
       _toast = toast ?? LocalNotifierToast(),
       _restoreWindow =
           restoreWindow ?? (() => TrayService.instance.restore()) {
    _cancels = [
      _realtime.on('friend_request', (_) => unawaited(onFriendRequest())),
      _realtime.on('friend_added', (_) => unawaited(onFriendAdded())),
      _realtime.on('push', (_) => unawaited(onPush())),
    ];
    for (final l in [_auth, _friends, _push]) {
      l.addListener(notifyListeners);
    }
    _sub = _auth.isLoggedIn ? _auth.sub : null;
    _auth.addListener(_onAuthChanged);
    _friends.addListener(_pruneNotified);
    _push.addListener(_pruneNotified);
  }

  static final NotificationService instance = NotificationService();

  /// 推送通知內文取附言的前幾個字
  static const messagePreviewLength = 40;

  final AuthService _auth;
  final RealtimeService _realtime;
  final FriendService _friends;
  final PushService _push;
  final ToastPlatform _toast;
  final Future<void> Function() _restoreWindow;
  late final List<void Function()> _cancels;

  /// 已經通知過的邀請（accountId）與推送（id），避免連續事件造成重複通知。
  /// 該筆離開 incoming／inbox 時移除（拒絕後再邀仍會通知），登出或換帳號時清空
  final Set<String> _notifiedInvites = {};
  final Set<String> _notifiedPushes = {};
  String? _sub;

  /// 點通知後要切到的畫面；消費者處理完設回 null
  final ValueNotifier<NotificationTarget?> intent = ValueNotifier(null);

  /// 側欄「好友」紅點的數字：收到的邀請數加未讀推送數；未登入為 0
  int get badgeCount =>
      _auth.isLoggedIn ? _friends.incoming.length + _push.unreadCount : 0;

  void _onAuthChanged() {
    final sub = _auth.isLoggedIn ? _auth.sub : null;
    if (sub == _sub) return;
    _sub = sub;
    _notifiedInvites.clear();
    _notifiedPushes.clear();
  }

  void _pruneNotified() {
    _notifiedInvites.retainAll(
      _friends.incoming.map((p) => p.accountId.toLowerCase()),
    );
    _notifiedPushes.retainAll(_push.items.map((p) => p.id));
  }

  Future<void> onFriendAdded() => _friends.refresh();

  Future<void> onFriendRequest() async {
    final baseline = _friends.loaded
        ? _friends.incoming.map((p) => p.accountId.toLowerCase()).toSet()
        : null;
    await _friends.refresh();
    if (baseline == null || !_auth.isLoggedIn) return;
    for (final p in _friends.incoming) {
      final id = p.accountId.toLowerCase();
      if (baseline.contains(id) || !_notifiedInvites.add(id)) continue;
      unawaited(
        _toast.show(
          title: '${p.displayName} 想加你為好友',
          body: '點擊查看收到的邀請',
          onClick: () => _open(NotificationTarget.invites),
        ),
      );
    }
  }

  Future<void> onPush() async {
    final baseline = _push.loaded ? _push.items.map((p) => p.id).toSet() : null;
    await _push.refresh();
    if (baseline == null || !_auth.isLoggedIn) return;
    for (final item in _push.items) {
      if (item.read ||
          baseline.contains(item.id) ||
          !_notifiedPushes.add(item.id)) {
        continue;
      }
      unawaited(
        _toast.show(
          title: '${item.from.displayName} 推送了圖譜給你',
          body: _pushBody(item),
          onClick: () => _open(NotificationTarget.inbox),
        ),
      );
    }
  }

  static String _pushBody(PushItem item) {
    final msg = item.message.trim();
    if (msg.isEmpty) return '${item.entries.length} 張圖譜';
    final runes = msg.runes.toList();
    return runes.length <= messagePreviewLength
        ? msg
        : '${String.fromCharCodes(runes.take(messagePreviewLength))}…';
  }

  Future<void> _open(NotificationTarget target) async {
    try {
      await _restoreWindow();
    } catch (e) {
      debugPrint('還原視窗失敗：$e');
    }
    intent.value = target;
  }

  @override
  void dispose() {
    for (final c in _cancels) {
      c();
    }
    for (final l in [_auth, _friends, _push]) {
      l.removeListener(notifyListeners);
    }
    _auth.removeListener(_onAuthChanged);
    _friends.removeListener(_pruneNotified);
    _push.removeListener(_pruneNotified);
    intent.dispose();
    super.dispose();
  }
}
