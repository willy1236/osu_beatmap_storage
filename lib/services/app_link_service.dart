import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import '../utils/friend_link.dart';
import '../utils/share_link.dart';
import 'auth_service.dart';
import 'friend_link_opener.dart';
import 'share_link_opener.dart';

/// 接收 `osu-storage://share/<token>`（冷啟動的命令列參數，或已開啟的程式收到轉交的連結），
/// 交給 [ShareLinkOpener.open]；`osu-storage://friend/<token>` 交給 [FriendLinkOpener.open]。
///
/// - 非分享、非好友邀請連結（scheme 或格式不符）一律忽略
/// - 先等登入狀態還原（`AuthService.ready`），避免誤顯示「需要先登入」
/// - navigator 還沒掛上時（[ShareLinkOpener.open] 回 false）等下一個 frame 再試，最多 [maxAttempts] 次
class AppLinkService {
  AppLinkService({
    Stream<Uri>? links,
    Future<void> Function()? ready,
    Future<bool> Function(String token)? open,
    Future<bool> Function(String token)? openFriend,
    Future<void> Function()? nextFrame,
    this.maxAttempts = 100,
  }) : _links = links,
       _ready = ready ?? (() => AuthService.instance.ready),
       _open = open ?? ((t) => ShareLinkOpener.instance.open(t)),
       _openFriend = openFriend ?? ((t) => FriendLinkOpener.instance.open(t)),
       _nextFrame = nextFrame ?? _waitNextFrame;

  static final AppLinkService instance = AppLinkService();

  final Stream<Uri>? _links;
  final Future<void> Function() _ready;
  final Future<bool> Function(String token) _open;
  final Future<bool> Function(String token) _openFriend;
  final Future<void> Function() _nextFrame;
  final int maxAttempts;

  StreamSubscription<Uri>? _sub;

  /// 開始監聽（盡早呼叫以接到冷啟動的連結）。重複呼叫無效。
  void start() {
    if (_sub != null) return;
    _sub = (_links ?? AppLinks().uriLinkStream).listen(
      (uri) => handle(uri.toString()),
      onError: (_) {},
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// 處理一條連結；回傳是否已交給 [ShareLinkOpener] 或 [FriendLinkOpener]
  Future<bool> handle(String link) async {
    var open = _open;
    var token = parseShareLink(link);
    if (token == null) {
      open = _openFriend;
      token = parseFriendLink(link);
    }
    if (token == null) return false;
    await _ready();
    for (var i = 0; i < maxAttempts; i++) {
      if (await open(token)) return true;
      await _nextFrame();
    }
    return false;
  }

  static Future<void> _waitNextFrame() {
    final c = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.complete());
    WidgetsBinding.instance.scheduleFrame();
    return c.future;
  }
}
