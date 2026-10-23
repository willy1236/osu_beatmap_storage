import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:osu_beatmap_storage/models/cloud_entry.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';
import 'package:osu_beatmap_storage/widgets/push_dialog.dart';

import 'friend_test_helpers.dart';

CloudEntry entry(int id) =>
    CloudEntry(onlineId: id, dateAdded: DateTime.utc(2026, 10, 1));

void main() {
  late List<http.Request> calls;
  late http.Response? Function(http.Request r) handler;

  setUp(() {
    calls = [];
    handler = (_) => null;
  });

  Future<(PushService, FriendService)> make(WidgetTester t) async {
    final auth = makeAuth();
    await auth.init();
    final api = makeApi((r) async {
      calls.add(r);
      final o = handler(r);
      if (o != null) return o;
      return switch ((r.method, r.url.path)) {
        ('GET', '/social/friends') => jsonResp({
          'friends': [
            peerJson(bId, '小明', timeKey: 'since'),
            peerJson(cId, '小華', timeKey: 'since'),
          ],
        }),
        ('GET', '/social/requests') => jsonResp({
          'incoming': [],
          'outgoing': [],
        }),
        ('GET', '/osu/pushes') => jsonResp({'pushes': []}),
        _ => jsonResp({'id': 'x'}),
      };
    });
    final fs = FriendService(api: api, auth: auth);
    final ps = PushService(
      api: api,
      auth: auth,
      friends: fs,
      onCollected: () {},
    );
    await t.runAsync(pumpEventQueue);
    return (ps, fs);
  }

  Future<void> open(
    WidgetTester t,
    PushService ps,
    FriendService fs,
    List<CloudEntry> entries,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showPushDialog(
                ctx,
                entries: entries,
                service: ps,
                friends: fs,
              ),
              child: const Text('開'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('開'));
    await t.pumpAndSettle();
  }

  FilledButton sendButton(WidgetTester t) =>
      t.widget<FilledButton>(find.widgetWithText(FilledButton, '送出'));

  testWidgets('沒選好友時不能送出並提示；選了才能送，成功後關閉', (t) async {
    final (ps, fs) = await make(t);
    await open(t, ps, fs, [entry(1), entry(2)]);
    expect(find.text('請選擇至少一位好友'), findsOneWidget);
    expect(sendButton(t).onPressed, isNull);

    await t.tap(find.text('小明'));
    await t.tap(find.text('小華'));
    await t.enterText(find.byType(TextField), '看看這些');
    await t.pump();
    expect(sendButton(t).onPressed, isNotNull);

    await t.tap(find.text('送出'));
    await t.pumpAndSettle();
    final post = calls.lastWhere((c) => c.method == 'POST');
    expect(post.url.path, '/osu/pushes');
    expect(post.body, contains(bId));
    expect(post.body, contains(cId));
    expect(post.body, contains('看看這些'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('超過 100 張：停用送出並說明原因', (t) async {
    final (ps, fs) = await make(t);
    await open(t, ps, fs, [for (var i = 1; i <= 101; i++) entry(i)]);
    await t.tap(find.text('小明'));
    await t.pump();
    expect(find.textContaining('一次最多推送 100 張'), findsOneWidget);
    expect(sendButton(t).onPressed, isNull);
  });

  testWidgets('附言超過 200 字：停用送出並說明原因', (t) async {
    final (ps, fs) = await make(t);
    await open(t, ps, fs, [entry(1)]);
    await t.tap(find.text('小明'));
    await t.enterText(find.byType(TextField), 'a' * 201);
    await t.pump();
    expect(find.textContaining('附言最多 200 字'), findsOneWidget);
    expect(sendButton(t).onPressed, isNull);
    await t.enterText(find.byType(TextField), 'a' * 200);
    await t.pump();
    expect(sendButton(t).onPressed, isNotNull);
  });

  testWidgets('後端回 not_friend：對話框保留並列出代號', (t) async {
    final (ps, fs) = await make(t);
    await open(t, ps, fs, [entry(1)]);
    await t.tap(find.text('小明'));
    await t.pump();
    handler = (r) => r.method == 'POST'
        ? jsonResp({'err': 'not_friend', 'description': '不是好友：$bId'}, 403)
        : null;
    await t.tap(find.text('送出'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('不是你的好友'), findsOneWidget);
    expect(find.textContaining('小明'), findsWidgets);
  });
}
