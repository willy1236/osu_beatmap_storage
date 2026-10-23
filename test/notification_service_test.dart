import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/notification_service.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';
import 'package:osu_beatmap_storage/services/realtime_service.dart';
import 'package:osu_beatmap_storage/services/toast_platform.dart';

import 'friend_test_helpers.dart';

class FakeToast implements ToastPlatform {
  final shown = <({String title, String body, VoidCallback onClick})>[];
  @override
  Future<void> show({
    required String title,
    required String body,
    required VoidCallback onClick,
  }) async => shown.add((title: title, body: body, onClick: onClick));
}

Map<String, dynamic> pushJson(String id, String from, String msg,
        {bool read = false}) =>
    {
      'id': id,
      'from': {'account_id': bId, 'username': from, 'picture': null},
      'message': msg,
      'entries': [
        {
          'online_id': 1,
          'title': 't',
          'date_added': '2026-10-01T00:00:00Z',
        },
      ],
      'created_at': '2026-10-02T00:00:00Z',
      'read': read,
    };

void main() {
  late FakeFriendBackend be;
  List<dynamic> pushes = [];
  late FakeToast toast;
  late int restored;

  setUp(() {
    be = FakeFriendBackend();
    pushes = [];
    toast = FakeToast();
    restored = 0;
    be.override = (r) {
      if (r.method == 'GET' && r.url.path == '/osu/pushes') {
        return jsonResp({'pushes': pushes});
      }
      return null;
    };
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  Future<
    ({NotificationService n, FriendService f, PushService p, AuthService a})
  >
  make({bool loggedIn = true}) async {
    final auth = makeAuth(loggedIn: loggedIn);
    await auth.init();
    final rt = RealtimeService(auth: makeAuth(loggedIn: false));
    final f = FriendService(api: be.api, auth: auth);
    final p = PushService(
      api: be.api,
      auth: auth,
      friends: f,
      onCollected: () {},
    );
    final n = NotificationService(
      auth: auth,
      realtime: rt,
      friends: f,
      push: p,
      toast: toast,
      restoreWindow: () async => restored++,
    );
    addTearDown(() {
      n.dispose();
      rt.dispose();
      p.dispose();
      f.dispose();
    });
    await settle();
    return (n: n, f: f, p: p, a: auth);
  }

  test('登入時已有的邀請與推送：只有紅點數字，沒有 toast', () async {
    be.requests = {
      'incoming': [peerJson(bId, '小明')],
      'outgoing': [],
    };
    pushes = [pushJson('p1', '小明', '嗨'), pushJson('p2', '小明', '嗨', read: true)];
    final s = await make();
    expect(s.n.badgeCount, 2);
    expect(toast.shown, isEmpty);
  });

  test('friend_request：重讀後對新邀請發 toast，含代號；已通知過不重複', () async {
    final s = await make();
    be.requests = {
      'incoming': [peerJson(bId, '小明')],
      'outgoing': [],
    };
    await s.n.onFriendRequest();
    expect(toast.shown, hasLength(1));
    expect(toast.shown.single.title, contains('小明'));
    expect(s.n.badgeCount, 1);
    await s.n.onFriendRequest();
    expect(toast.shown, hasLength(1));
  });

  test('push：新的未讀推送發 toast，附言取前 40 字；無附言顯示圖譜數', () async {
    final s = await make();
    pushes = [pushJson('p1', '小華', '字' * 50), pushJson('p2', '小美', '')];
    await s.n.onPush();
    expect(toast.shown, hasLength(2));
    expect(toast.shown[0].title, contains('小華'));
    expect(toast.shown[0].body, '${'字' * 40}…');
    expect(toast.shown[1].body, '1 張圖譜');
    expect(s.n.badgeCount, 2);
  });

  test('列表還沒讀到時收到事件：重讀但不發 toast', () async {
    final auth = makeAuth(loggedIn: false);
    await auth.init();
    final rt = RealtimeService(auth: auth);
    final f = FriendService(api: be.api, auth: auth);
    final p = PushService(api: be.api, auth: auth, friends: f);
    final n = NotificationService(
      auth: auth,
      realtime: rt,
      friends: f,
      push: p,
      toast: toast,
      restoreWindow: () async {},
    );
    addTearDown(() {
      n.dispose();
      rt.dispose();
    });
    await n.onFriendRequest();
    await n.onPush();
    expect(toast.shown, isEmpty);
    expect(n.badgeCount, 0);
  });

  test('friend_added：重讀好友列表，不發 toast', () async {
    final s = await make();
    be.friends = [peerJson(bId, '小明', timeKey: 'since')];
    await s.n.onFriendAdded();
    expect(s.f.friends, hasLength(1));
    expect(toast.shown, isEmpty);
  });

  test('點通知：還原視窗並設定 intent', () async {
    final s = await make();
    be.requests = {
      'incoming': [peerJson(bId, '小明')],
      'outgoing': [],
    };
    await s.n.onFriendRequest();
    toast.shown.single.onClick();
    await settle();
    expect(restored, 1);
    expect(s.n.intent.value, NotificationTarget.invites);
    s.n.intent.value = null;
    pushes = [pushJson('p1', '小華', '嗨')];
    await s.n.onPush();
    toast.shown.last.onClick();
    await settle();
    expect(s.n.intent.value, NotificationTarget.inbox);
  });

  test('處理完（邀請移除、推送已讀）後紅點歸零；未登入為 0', () async {
    be.requests = {
      'incoming': [peerJson(bId, '小明')],
      'outgoing': [],
    };
    pushes = [pushJson('p1', '小華', '嗨')];
    final s = await make();
    expect(s.n.badgeCount, 2);
    be.requests = {'incoming': [], 'outgoing': []};
    pushes = [pushJson('p1', '小華', '嗨', read: true)];
    await s.f.refresh();
    await s.p.refresh();
    expect(s.n.badgeCount, 0);
    final out = await make(loggedIn: false);
    expect(out.n.badgeCount, 0);
  });

  test('透過 SSE 事件分派：friend_request 事件觸發 toast', () async {
    final auth = makeAuth();
    await auth.init();
    final body = StreamController<List<int>>();
    final rt = RealtimeService(
      auth: auth,
      clientFactory: () => MockClient.streaming(
        (req, _) async => http.StreamedResponse(body.stream, 200),
      ),
      baseUrl: 'https://api.test',
    );
    final f = FriendService(api: be.api, auth: auth);
    final p = PushService(api: be.api, auth: auth, friends: f);
    final n = NotificationService(
      auth: auth,
      realtime: rt,
      friends: f,
      push: p,
      toast: toast,
      restoreWindow: () async {},
    );
    addTearDown(() {
      n.dispose();
      rt.dispose();
    });
    await settle();
    be.requests = {
      'incoming': [peerJson(bId, '小明')],
      'outgoing': [],
    };
    body.add(utf8.encode('event: friend_request\ndata: {}\n\n'));
    await settle();
    expect(toast.shown, hasLength(1));
  });
}
