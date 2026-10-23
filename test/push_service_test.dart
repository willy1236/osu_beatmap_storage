import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:osu_beatmap_storage/models/cloud_entry.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';

import 'friend_test_helpers.dart';

Map<String, dynamic> entryJson(int id, {String title = 't'}) => {
  'online_id': id,
  'title': title,
  'date_added': '2026-10-01T00:00:00Z',
};

Map<String, dynamic> pushJson(
  String id, {
  bool read = false,
  String from = '小明',
  List<Map<String, dynamic>>? entries,
}) => {
  'id': id,
  'from': {'account_id': bId, 'username': from, 'picture': null},
  'message': '推薦',
  'entries': entries ?? [entryJson(1), entryJson(2)],
  'created_at': '2026-10-02T00:00:00Z',
  'read': read,
};

CloudEntry entry(int id) =>
    CloudEntry(onlineId: id, dateAdded: DateTime.utc(2026, 10, 1));

void main() {
  late List<http.Request> calls;
  late http.Response? Function(http.Request r) handler;
  List<dynamic> pushes = [];
  List<dynamic> friends = [];

  setUp(() {
    calls = [];
    pushes = [];
    friends = [];
    handler = (_) => null;
  });

  Future<http.Response> handle(http.Request r) async {
    calls.add(r);
    final o = handler(r);
    if (o != null) return o;
    if (r.method == 'GET' && r.url.path == '/osu/pushes') {
      return jsonResp({'pushes': pushes});
    }
    if (r.method == 'GET' && r.url.path == '/social/friends') {
      return jsonResp({'friends': friends});
    }
    if (r.method == 'GET' && r.url.path == '/social/requests') {
      return jsonResp({'incoming': [], 'outgoing': []});
    }
    return http.Response('', 204);
  }

  Future<PushService> make({
    bool loggedIn = true,
    void Function()? onCollected,
  }) async {
    final auth = makeAuth(loggedIn: loggedIn);
    await auth.init();
    final api = makeApi(handle);
    final fs = FriendService(api: api, auth: auth);
    final s = PushService(
      api: api,
      auth: auth,
      friends: fs,
      onCollected: onCollected ?? () {},
    );
    await pumpEventQueue();
    return s;
  }

  test('未登入：不讀取', () async {
    final s = await make(loggedIn: false);
    await s.refresh();
    expect(calls, isEmpty);
    expect(s.loaded, isFalse);
  });

  test('登入後讀取全部收件匣（不傳 limit），算出未讀數', () async {
    pushes = [pushJson('p1'), pushJson('p2', read: true)];
    final s = await make();
    final get = calls.firstWhere((c) => c.url.path == '/osu/pushes');
    expect(get.url.query, isEmpty);
    expect(s.loaded, isTrue);
    expect(s.items, hasLength(2));
    expect(s.items.first.from.username, '小明');
    expect(s.items.first.entries.map((e) => e.onlineId), [1, 2]);
    expect(s.unreadCount, 1);
  });

  test('讀取失敗保留上次結果並設 error，成功後清除', () async {
    pushes = [pushJson('p1')];
    final s = await make();
    handler = (r) => r.url.path == '/osu/pushes'
        ? jsonResp({'err': 'unavailable'}, 503)
        : null;
    await s.refresh();
    expect(s.items, hasLength(1));
    expect(s.error, '服務暫時無法使用，請稍後再試');
    handler = (_) => null;
    await s.refresh();
    expect(s.error, isNull);
  });

  test('markRead：本機立即已讀並呼叫後端；已讀的不重送', () async {
    pushes = [pushJson('p1')];
    final s = await make();
    expect(await s.markRead('p1'), isTrue);
    expect(s.unreadCount, 0);
    expect(
      calls.where((c) => c.url.path == '/osu/pushes/p1/read'),
      hasLength(1),
    );
    await s.markRead('p1');
    expect(
      calls.where((c) => c.url.path == '/osu/pushes/p1/read'),
      hasLength(1),
    );
  });

  test('markRead 失敗時還原為未讀', () async {
    pushes = [pushJson('p1')];
    final s = await make();
    handler = (r) => r.url.path.endsWith('/read')
        ? jsonResp({'err': 'not_found'}, 404)
        : null;
    expect(await s.markRead('p1'), isFalse);
    expect(s.unreadCount, 1);
  });

  test('delete：成功後從本機列表移除', () async {
    pushes = [pushJson('p1'), pushJson('p2')];
    final s = await make();
    expect(await s.delete('p1'), isTrue);
    expect(s.items.map((p) => p.id), ['p2']);
    expect(calls.last.method, 'DELETE');
  });

  test('collect：成功回報筆數並通知；429 回 rateLimited 不通知', () async {
    pushes = [pushJson('p1')];
    var notified = 0;
    final s = await make(onCollected: () => notified++);
    handler = (r) => r.url.path.endsWith('/collect')
        ? jsonResp({'inserted': 3, 'updated': 1})
        : null;
    final ok = await s.collect('p1');
    expect(ok.ok, isTrue);
    expect((ok.inserted, ok.updated), (3, 1));
    expect(notified, 1);
    handler = (r) => r.url.path.endsWith('/collect')
        ? jsonResp({'err': 'rate_limited'}, 429)
        : null;
    final limited = await s.collect('p1');
    expect(limited.status, CollectStatus.rateLimited);
    expect(limited.message, '請稍後再試');
    expect(notified, 1);
  });

  group('send', () {
    test('成功：送出 to、message、entries（UTC 時間）', () async {
      final s = await make();
      handler = (r) => r.method == 'POST' ? jsonResp({'id': 'x'}, 200) : null;
      final r = await s.send(
        toAccountIds: [bId, cId],
        message: '看看',
        entries: [entry(5)],
      );
      expect(r.ok, isTrue);
      final body = jsonDecode(calls.last.body) as Map<String, dynamic>;
      expect(body['to'], [bId, cId]);
      expect(body['message'], '看看');
      expect((body['entries'] as List).single['online_id'], 5);
      expect(
        (body['entries'] as List).single['date_added'],
        '2026-10-01T00:00:00.000Z',
      );
    });

    test('本機先擋：超過 100 張、超過 200 字、OnlineID<=0、沒收件人，不送出', () async {
      final s = await make();
      calls.clear();
      Future<PushSendResult> go({
        List<String> to = const [bId],
        String msg = '',
        List<CloudEntry>? entries,
      }) => s.send(
        toAccountIds: to,
        message: msg,
        entries: entries ?? [entry(1)],
      );
      expect(
        (await go(entries: [for (var i = 1; i <= 101; i++) entry(i)])).status,
        PushSendStatus.invalid,
      );
      expect((await go(msg: 'a' * 201)).status, PushSendStatus.invalid);
      expect((await go(entries: [entry(0)])).status, PushSendStatus.invalid);
      expect((await go(to: [])).status, PushSendStatus.invalid);
      // 剛好 100 張、200 字不擋
      handler = (r) => jsonResp({'id': 'x'});
      expect(
        (await go(
          msg: 'a' * 200,
          entries: [for (var i = 1; i <= 100; i++) entry(i)],
        )).ok,
        isTrue,
      );
      expect(calls.where((c) => c.method == 'POST'), hasLength(1));
    });

    test('403 not_friend：以好友列表反查代號，查不到顯示 id', () async {
      friends = [peerJson(bId, '小明', timeKey: 'since')];
      final s = await make();
      handler = (r) => r.method == 'POST'
          ? jsonResp({
              'err': 'not_friend',
              'description': '不是好友：$bId、$cId',
            }, 403)
          : null;
      final r = await s.send(
        toAccountIds: [bId, cId],
        message: '',
        entries: [entry(1)],
      );
      expect(r.status, PushSendStatus.notFriend);
      expect(r.notFriendIds, [bId, cId]);
      expect(r.message, contains('小明'));
      expect(r.message, contains(cId));
      expect(r.message, isNot(contains(bId)));
    });

    test('其他失敗回 failed 與說明', () async {
      final s = await make();
      handler = (r) =>
          r.method == 'POST' ? jsonResp({'err': 'unavailable'}, 503) : null;
      final r = await s.send(
        toAccountIds: [bId],
        message: '',
        entries: [entry(1)],
      );
      expect(r.status, PushSendStatus.failed);
      expect(r.message, '服務暫時無法使用，請稍後再試');
    });
  });
}
