import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:osu_beatmap_storage/pages/friends_page.dart';
import 'package:osu_beatmap_storage/services/friend_lookup.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/widgets/add_friend_dialog.dart';

import 'friend_test_helpers.dart';

void main() {
  late FakeFriendBackend be;
  late FriendService service;
  late List<http.Request> posts;

  setUp(() => be = FakeFriendBackend());

  /// 後端對 lookup 的回應由 [lookupReply] 決定；回 null 時丟逾時例外
  Future<void> open(
    WidgetTester t, {
    http.Response? Function(http.Request r)? lookupReply,
  }) async {
    posts = [];
    be.override = (r) {
      if (r.url.path == '/social/lookup') {
        return lookupReply?.call(r) ?? (throw TimeoutException('x'));
      }
      if (r.method == 'POST' && r.url.path == '/social/requests') {
        posts.add(r);
        return jsonResp({'status': 'sent'});
      }
      return null;
    };
    final auth = makeAuth();
    await auth.init();
    service = FriendService(api: be.api, auth: auth);
    await t.runAsync(pumpEventQueue);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAddFriendDialog(
                context,
                service: service,
                lookup: FriendLookup(api: be.api),
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

  Future<void> query(WidgetTester t, String name) async {
    await t.enterText(find.byType(TextField), name);
    await t.tap(find.widgetWithText(FilledButton, '查詢'));
    await t.pumpAndSettle();
  }

  bool confirmEnabled(WidgetTester t) =>
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '確認'))
          .onPressed !=
      null;

  group('FriendLookup', () {
    test('200 解析 Peer，帶 username 查詢參數', () async {
      late http.Request req;
      final l = FriendLookup(
        api: makeApi((r) async {
          req = r;
          return jsonResp({
            'account_id': bId,
            'username': '小明',
            'picture': 'https://x/p.png',
          });
        }),
      );
      final r = await l.find('小明');
      expect(req.url.queryParameters['username'], '小明');
      expect(r.peer!.accountId, bId);
      expect(r.peer!.picture, 'https://x/p.png');
    });

    test('404 為找不到；503 與連線例外為請稍後再試且不算找不到', () async {
      final nf = await FriendLookup(
        api: makeApi((_) async => jsonResp({'err': 'not_found'}, 404)),
      ).find('x');
      expect(nf.error, '找不到這位域民');
      expect(nf.notFound, isTrue);

      final un = await FriendLookup(
        api: makeApi((_) async => jsonResp({'err': 'unavailable'}, 503)),
      ).find('x');
      expect(un.error, '請稍後再試');
      expect(un.notFound, isFalse);

      final ex = await FriendLookup(
        api: makeApi((_) async => throw http.ClientException('down')),
      ).find('x');
      expect(ex.error, '請稍後再試');
      expect(ex.notFound, isFalse);
    });
  });

  group('FriendService.sendToAccount', () {
    test('POST body 帶 account_id，成功後重讀並出現在送出的邀請', () async {
      final auth = makeAuth();
      await auth.init();
      late http.Request post;
      be.override = (r) {
        if (r.method == 'POST' && r.url.path == '/social/requests') {
          post = r;
          be.requests = {
            'incoming': [],
            'outgoing': [peerJson(bId, '小明')],
          };
          return jsonResp({'status': 'sent'});
        }
        return null;
      };
      final s = FriendService(api: be.api, auth: auth);
      await s.refresh();
      final r = await s.sendToAccount(bId);
      expect(r.status, FriendActionStatus.sent);
      expect(jsonDecode(post.body), {'account_id': bId});
      expect(s.outgoing.map((p) => p.accountId), [bId]);
    });

    test('status friends 與 409 already_friends', () async {
      final auth = makeAuth();
      await auth.init();
      be.override = (r) =>
          r.method == 'POST' ? jsonResp({'status': 'friends'}) : null;
      final s = FriendService(api: be.api, auth: auth);
      expect((await s.sendToAccount(bId)).status, FriendActionStatus.friends);
      be.override = (r) =>
          r.method == 'POST' ? jsonResp({'err': 'already_friends'}, 409) : null;
      final r = await s.sendToAccount(bId);
      expect(r.ok, isFalse);
      expect(r.message, '你們已經是好友');
    });
  });

  group('加好友對話框', () {
    testWidgets('好友頁有加好友按鈕，按下開啟對話框', (t) async {
      final auth = makeAuth();
      await auth.init();
      final s = FriendService(api: be.api, auth: auth);
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(
        MaterialApp(
          home: FriendsPage(service: s, auth: auth),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('加好友'));
      await t.pumpAndSettle();
      expect(find.text('域民代號'), findsOneWidget);
    });

    testWidgets('查到後顯示代號，按確認才送出，送出後對方在送出的邀請', (t) async {
      await open(
        t,
        lookupReply: (_) =>
            jsonResp({'account_id': bId, 'username': '小明', 'picture': null}),
      );
      be.requests = {
        'incoming': [],
        'outgoing': [peerJson(bId, '小明')],
      };
      await query(t, ' 小明 ');
      expect(find.text('小明'), findsOneWidget);
      expect(posts, isEmpty); // 查到還沒送出
      await t.tap(find.widgetWithText(FilledButton, '確認'));
      await t.pumpAndSettle();
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body), {'account_id': bId});
      expect(find.text('已送出好友邀請'), findsOneWidget);
      expect(find.text('域民代號'), findsNothing); // 對話框已關
      expect(service.outgoing.map((p) => p.accountId), [bId]);
    });

    testWidgets('找不到：顯示找不到，不出現確認', (t) async {
      await open(t, lookupReply: (_) => jsonResp({'err': 'not_found'}, 404));
      await query(t, 'nobody');
      expect(find.text('找不到這位域民'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '確認'), findsNothing);
    });

    testWidgets('後端連不上：請稍後再試，不顯示找不到', (t) async {
      await open(t, lookupReply: (_) => jsonResp({'err': 'unavailable'}, 503));
      await query(t, 'bob');
      expect(find.text('請稍後再試'), findsOneWidget);
      expect(find.text('找不到這位域民'), findsNothing);
    });

    testWidgets('自己：提示且確認停用，不送出', (t) async {
      await open(
        t,
        lookupReply: (_) => jsonResp({'account_id': meId, 'username': 'me'}),
      );
      await query(t, 'me');
      expect(find.text('不能對自己送邀請'), findsOneWidget);
      expect(confirmEnabled(t), isFalse);
      expect(posts, isEmpty);
    });

    testWidgets('已是好友：提示且確認停用', (t) async {
      be.friends = [peerJson(bId, '小明', timeKey: 'since')];
      await open(
        t,
        lookupReply: (_) => jsonResp({'account_id': bId, 'username': '小明'}),
      );
      await query(t, '小明');
      expect(find.text('你們已經是好友'), findsOneWidget);
      expect(confirmEnabled(t), isFalse);
      expect(posts, isEmpty);
    });

    testWidgets('對方已邀請我：提示後允許送出', (t) async {
      be.requests = {
        'incoming': [peerJson(bId, '小明')],
        'outgoing': [],
      };
      await open(
        t,
        lookupReply: (_) => jsonResp({'account_id': bId, 'username': '小明'}),
      );
      await query(t, '小明');
      expect(find.text('對方已邀請你，按確認將直接成為好友'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '確認'));
      await t.pumpAndSettle();
      expect(posts, hasLength(1));
    });
  });
}
