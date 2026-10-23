import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/lazer_detector.dart';
import 'package:osu_beatmap_storage/services/notification_service.dart';
import 'package:osu_beatmap_storage/services/presence_service.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';
import 'package:osu_beatmap_storage/services/realtime_service.dart';
import 'package:osu_beatmap_storage/services/toast_platform.dart';

import 'friend_test_helpers.dart';

class _Conn {
  final body = StreamController<List<int>>();
  void push(String s) => body.add(utf8.encode(s));
  Future<void> end() => body.close();
}

class _Toast implements ToastPlatform {
  final titles = <String>[];
  @override
  Future<void> show({
    required String title,
    required String body,
    required VoidCallback onClick,
  }) async => titles.add(title);
}

class _Idle implements LazerDetector {
  @override
  Future<bool> isRunning() async => false;
}

Map<String, dynamic> _push(String id, String from) => {
  'id': id,
  'from': {'account_id': bId, 'username': from, 'picture': null},
  'message': '嗨',
  'entries': [
    {'online_id': 1, 'title': 't', 'date_added': '2026-10-01T00:00:00Z'},
  ],
  'created_at': '2026-10-02T00:00:00Z',
  'read': false,
};

/// T-12 / T-09：重連（resyncRequested）時，好友列表與收件匣各自整份重讀一次，
/// 紅點更新、不發 toast；重讀進行中收到事件時，斷線期間的項目也不發 toast。
/// 全部在 fake 時間裡跑，不依賴真實時間
void main() {
  late List<_Conn> conns;
  late List<http.Request> calls;
  late List<dynamic> pushes;
  late Map<String, List<dynamic>> requests;

  /// 設定後，下一次對應列表的 GET 先取好當下的資料，等 gate 完成才回應
  Completer<void>? pushGate;
  Completer<void>? requestsGate;

  setUp(() {
    conns = [];
    calls = [];
    pushes = [];
    requests = {'incoming': [], 'outgoing': []};
    pushGate = null;
    requestsGate = null;
  });

  Future<http.Response> handle(http.Request r) async {
    calls.add(r);
    if (r.method == 'GET' && r.url.path == '/osu/pushes') {
      final snapshot = jsonResp({'pushes': List.of(pushes)});
      final g = pushGate;
      pushGate = null;
      if (g != null) await g.future;
      return snapshot;
    }
    if (r.method == 'GET' && r.url.path == '/social/requests') {
      final snapshot = jsonResp({
        'incoming': List.of(requests['incoming']!),
        'outgoing': List.of(requests['outgoing']!),
      });
      final g = requestsGate;
      requestsGate = null;
      if (g != null) await g.future;
      return snapshot;
    }
    if (r.method == 'GET' && r.url.path == '/social/friends') {
      return jsonResp({'friends': []});
    }
    if (r.url.path == '/social/settings') {
      return jsonResp({'presence_visible': true});
    }
    return http.Response('', 204);
  }

  T await_<T>(FakeAsync async, Future<T> f) {
    late T value;
    var done = false;
    Object? error;
    f.then((v) {
      value = v;
      done = true;
    }, onError: (Object e) => error = e);
    async.flushMicrotasks();
    if (error != null) throw error!;
    expect(done, isTrue, reason: 'Future 沒有完成');
    return value;
  }

  void settle(FakeAsync async) => async.elapse(const Duration(seconds: 1));

  int count(String path) =>
      calls.where((c) => c.method == 'GET' && c.url.path == path).length;

  void fakeTest(
    String name,
    void Function(
      FakeAsync async,
      FriendService f,
      PushService p,
      NotificationService n,
      _Toast toast,
    )
    body,
  ) {
    test(name, () {
      fakeAsync((async) {
        final auth = makeAuth();
        await_(async, auth.init());
        final rt = RealtimeService(
          auth: auth,
          clientFactory: () => MockClient.streaming((req, _) async {
            final c = _Conn();
            conns.add(c);
            return http.StreamedResponse(c.body.stream, 200);
          }),
          baseUrl: 'https://api.test',
          backoff: (_) => const Duration(milliseconds: 5),
        );
        final api = makeApi(handle);
        final f = FriendService(api: api, auth: auth, realtime: rt);
        final p = PushService(
          api: api,
          auth: auth,
          friends: f,
          realtime: rt,
          onCollected: () {},
        );
        final toast = _Toast();
        final n = NotificationService(
          auth: auth,
          realtime: rt,
          friends: f,
          push: p,
          toast: toast,
          restoreWindow: () async {},
        );
        // PresenceService 不再自己重讀好友列表，不能造成重複請求
        final presence = PresenceService(
          api: api,
          auth: auth,
          realtime: rt,
          friends: f,
          detector: _Idle(),
          interval: const Duration(seconds: 30),
        );
        settle(async);
        expect(conns, hasLength(1));
        body(async, f, p, n, toast);
        presence.dispose();
        n.dispose();
        p.dispose();
        f.dispose();
        rt.dispose();
        async.flushTimers();
      });
    });
  }

  fakeTest('重連：FriendService、PushService 各重讀一次，紅點更新，不發 toast', (
    async,
    f,
    p,
    n,
    toast,
  ) {
    expect(n.badgeCount, 0);
    final friendsBefore = count('/social/friends');
    final requestsBefore = count('/social/requests');
    final pushesBefore = count('/osu/pushes');

    // 斷線期間錯過的邀請與推送
    requests = {
      'incoming': [peerJson(bId, '小明')],
      'outgoing': [],
    };
    pushes = [_push('p1', '小明')];
    conns[0].end();
    settle(async);

    expect(conns, hasLength(2));
    expect(f.incoming, hasLength(1));
    expect(p.unreadCount, 1);
    expect(n.badgeCount, 2);
    expect(toast.titles, isEmpty);
    expect(count('/social/friends'), friendsBefore + 1);
    expect(count('/social/requests'), requestsBefore + 1);
    expect(count('/osu/pushes'), pushesBefore + 1);
  });

  fakeTest('重讀進行中收到 push：斷線期間的推送不發 toast，事件之後的新推送才發', (
    async,
    f,
    p,
    n,
    toast,
  ) {
    pushes = [_push('dis', '斷線時')]; // 斷線期間錯過的
    final gate = pushGate = Completer<void>();
    conns[0].end();
    async.elapse(const Duration(milliseconds: 50));
    expect(conns, hasLength(2));
    expect(p.loading, isTrue); // 重讀在途，回應被卡住

    // 重讀在途時，伺服器又多了一筆，並收到 push 事件
    pushes = [_push('dis', '斷線時'), _push('new', '新的')];
    conns[1].push('event: push\ndata: {}\n\n');
    async.flushMicrotasks();
    expect(toast.titles, isEmpty);

    gate.complete();
    settle(async);
    expect(p.items.map((e) => e.id), containsAll(['dis', 'new']));
    expect(toast.titles, hasLength(1));
    expect(toast.titles.single, contains('新的'));
  });

  fakeTest('重讀進行中收到 friend_request：斷線期間的邀請不發 toast，新的才發', (
    async,
    f,
    p,
    n,
    toast,
  ) {
    requests = {
      'incoming': [peerJson(bId, '斷線時')],
      'outgoing': [],
    };
    final gate = requestsGate = Completer<void>();
    conns[0].end();
    async.elapse(const Duration(milliseconds: 50));
    expect(f.loading, isTrue);

    requests = {
      'incoming': [peerJson(bId, '斷線時'), peerJson(cId, '新的')],
      'outgoing': [],
    };
    conns[1].push('event: friend_request\ndata: {}\n\n');
    async.flushMicrotasks();
    expect(toast.titles, isEmpty);

    gate.complete();
    settle(async);
    expect(f.incoming, hasLength(2));
    expect(toast.titles, hasLength(1));
    expect(toast.titles.single, contains('新的'));
  });
}
