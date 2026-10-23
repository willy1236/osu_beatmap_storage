import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:osu_beatmap_storage/pages/friends_page.dart';
import 'package:osu_beatmap_storage/pages/inbox_page.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';

import 'friend_test_helpers.dart';

Map<String, dynamic> entryJson(int id, String title) => {
  'online_id': id,
  'title': title,
  'title_unicode': title,
  'artist': 'A',
  'date_added': '2026-10-01T00:00:00Z',
};

Map<String, dynamic> pushJson(
  String id, {
  bool read = false,
  String msg = '',
}) => {
  'id': id,
  'from': {'account_id': bId, 'username': '小明', 'picture': null},
  'message': msg,
  'entries': [entryJson(11, '歌一'), entryJson(12, '歌二')],
  'created_at': '2026-10-02T03:04:00Z',
  'read': read,
};

void main() {
  late List<http.Request> calls;
  late List<dynamic> pushes;
  late http.Response? Function(http.Request r) handler;

  setUp(() {
    calls = [];
    pushes = [];
    handler = (_) => null;
  });

  Future<(PushService, AuthService)> make(WidgetTester t) async {
    final auth = makeAuth();
    await auth.init();
    final api = makeApi((r) async {
      calls.add(r);
      final o = handler(r);
      if (o != null) return o;
      if (r.method == 'GET' && r.url.path == '/osu/pushes') {
        return jsonResp({'pushes': pushes});
      }
      return jsonResp({'inserted': 2, 'updated': 0});
    });
    final ps = PushService(api: api, auth: auth, onCollected: () {});
    await t.runAsync(pumpEventQueue);
    return (ps, auth);
  }

  Future<void> pumpInbox(
    WidgetTester t,
    PushService ps,
    AuthService auth,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: InboxPage(service: ps, auth: auth, localIds: const {11}),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('顯示送出者代號、附言、圖譜數，未讀有標示', (t) async {
    pushes = [pushJson('p1', msg: '聽聽看'), pushJson('p2', read: true)];
    final (ps, auth) = await make(t);
    await pumpInbox(t, ps, auth);
    expect(find.text('收件匣（1 未讀）'), findsOneWidget);
    expect(find.text('小明'), findsNWidgets(2));
    expect(find.textContaining('聽聽看'), findsOneWidget);
    expect(find.textContaining('2 個圖譜集'), findsNWidgets(2));
    expect(find.text('未讀'), findsOneWidget);
  });

  testWidgets('空收件匣', (t) async {
    final (ps, auth) = await make(t);
    await pumpInbox(t, ps, auth);
    expect(find.text('收件匣是空的'), findsOneWidget);
  });

  testWidgets('點開：標為已讀、顯示圖譜清單', (t) async {
    pushes = [pushJson('p1')];
    final (ps, auth) = await make(t);
    await pumpInbox(t, ps, auth);
    await t.tap(find.text('小明'));
    await t.pumpAndSettle();
    expect(find.text('小明 的推送'), findsOneWidget);
    expect(find.text('歌一'), findsOneWidget);
    expect(find.text('歌二'), findsOneWidget);
    expect(calls.any((c) => c.url.path == '/osu/pushes/p1/read'), isTrue);
    expect(ps.unreadCount, 0);
  });

  testWidgets('收進我的清單：呼叫 collect 並顯示筆數', (t) async {
    pushes = [pushJson('p1')];
    final (ps, auth) = await make(t);
    await pumpInbox(t, ps, auth);
    await t.tap(find.text('小明'));
    await t.pumpAndSettle();
    await t.tap(find.text('收進我的清單'));
    await t.pumpAndSettle();
    expect(calls.any((c) => c.url.path == '/osu/pushes/p1/collect'), isTrue);
    expect(find.text('已收進我的清單：新增 2、更新 0'), findsOneWidget);
  });

  testWidgets('收進清單被限流：提示請稍後再試', (t) async {
    pushes = [pushJson('p1')];
    final (ps, auth) = await make(t);
    await pumpInbox(t, ps, auth);
    await t.tap(find.text('小明'));
    await t.pumpAndSettle();
    handler = (r) => r.url.path.endsWith('/collect')
        ? jsonResp({'err': 'rate_limited'}, 429)
        : null;
    await t.tap(find.text('收進我的清單'));
    await t.pumpAndSettle();
    expect(find.text('請稍後再試'), findsOneWidget);
  });

  testWidgets('刪除：確認後呼叫 DELETE、回到收件匣且該筆消失', (t) async {
    pushes = [pushJson('p1')];
    final (ps, auth) = await make(t);
    await pumpInbox(t, ps, auth);
    await t.tap(find.text('小明'));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.delete_outline));
    await t.pumpAndSettle();
    await t.tap(find.text('刪除'));
    await t.pumpAndSettle();
    expect(
      calls.any((c) => c.method == 'DELETE' && c.url.path == '/osu/pushes/p1'),
      isTrue,
    );
    expect(find.text('收件匣是空的'), findsOneWidget);
  });

  testWidgets('好友頁 AppBar 的收件匣圖示開啟收件匣', (t) async {
    pushes = [pushJson('p1')];
    final (ps, auth) = await make(t);
    final be = FakeFriendBackend();
    final fs = FriendService(api: be.api, auth: auth);
    await t.pumpWidget(
      MaterialApp(
        home: FriendsPage(service: fs, auth: auth, push: ps),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('收件匣'));
    await t.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
    expect(find.text('小明'), findsOneWidget);
  });
}
