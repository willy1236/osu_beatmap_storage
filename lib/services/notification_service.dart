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
    _friends.addListener(_onFriendsChanged);
    _push.addListener(_onPushChanged);
    _realtime.resyncRequested.addListener(_onResync);
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
  /// 該筆離開 incoming／inbox 時移除（拒絕後再邀仍會通知）。登出、換帳號時兩個 Service
  /// 會清空列表，由此移除保證，不需另外清空
  final Set<String> _notifiedInvites = {};
  final Set<String> _notifiedPushes = {};

  /// 重連（resyncRequested）當下 [FriendService]、[PushService] 在途的整份重讀
  /// （含合併進來的再讀一次）。事件處理要先等它結束才取基準：斷線期間錯過的項目屬於重讀，
  /// 不發通知，只有事件之後才出現的項目才發
  Future<void>? _friendsResync;
  Future<void>? _pushResync;
  bool _disposed = false;

  /// 點通知後要切到的畫面；消費者處理完設回 null
  final ValueNotifier<NotificationTarget?> intent = ValueNotifier(null);

  /// 側欄「好友」紅點的數字：收到的邀請數加未讀推送數；未登入為 0
  int get badgeCount =>
      _auth.isLoggedIn ? _friends.incoming.length + _push.unreadCount : 0;

  void _onResync() {
    if (!_auth.isLoggedIn) return;
    // 兩個 Service 各自訂閱同一個訊號並開始讀取；等同一輪的 Listener 都跑完再取在途的 Future
    scheduleMicrotask(() {
      if (_disposed) return;
      _friendsResync = _friends.loadInFlight;
      _pushResync = _push.loadInFlight;
    });
  }

  void _onFriendsChanged() {
    _notifiedInvites.retainAll(
      _friends.incoming.map((p) => p.accountId.toLowerCase()),
    );
  }

  void _onPushChanged() {
    _notifiedPushes.retainAll(_push.items.map((p) => p.id));
  }

  Future<void> onFriendAdded() => _friends.refresh();

  Future<void> onFriendRequest() async {
    await _friendsResync;
    if (_disposed) return;
    final baseline = _friends.loaded
        ? _friends.incoming.map((p) => p.accountId.toLowerCase()).toSet()
        : null;
    await _friends.refresh();
    if (_disposed || baseline == null || !_auth.isLoggedIn) return;
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
    await _pushResync;
    if (_disposed) return;
    final baseline = _push.loaded ? _push.items.map((p) => p.id).toSet() : null;
    await _push.refresh();
    if (_disposed || baseline == null || !_auth.isLoggedIn) return;
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
    _disposed = true;
    for (final c in _cancels) {
      c();
    }
    for (final l in [_auth, _friends, _push]) {
      l.removeListener(notifyListeners);
    }
    _friends.removeListener(_onFriendsChanged);
    _push.removeListener(_onPushChanged);
    _realtime.resyncRequested.removeListener(_onResync);
    intent.dispose();
    super.dispose();
  }
}
