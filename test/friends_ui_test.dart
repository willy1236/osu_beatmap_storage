import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/pages/friends_page.dart';
import 'package:osu_beatmap_storage/services/cloud_sync_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/shared_list_service.dart';
import 'package:osu_beatmap_storage/widgets/add_friend_button.dart';

import 'friend_test_helpers.dart';

void main() {
  late FakeFriendBackend be;

  setUp(() => be = FakeFriendBackend());

  Future<FriendService> makeService(WidgetTester t) async {
    final auth = makeAuth();
    await auth.init();
    final s = FriendService(api: be.api, auth: auth);
    await t.runAsync(pumpEventQueue);
    return s;
  }

  group('FriendsPage', () {
    testWidgets('未登入：只提示登入，不讀取', (t) async {
      final auth = makeAuth(loggedIn: false);
      await auth.init();
      final s = FriendService(api: be.api, auth: auth);
      await t.pumpWidget(
        MaterialApp(
          home: FriendsPage(service: s, auth: auth),
        ),
      );
      expect(find.text('登入析域帳號後才能使用好友功能'), findsOneWidget);
      expect(find.text('登入'), findsOneWidget);
      expect(be.calls, isEmpty);
    });

    testWidgets('顯示三個區塊與空代號退化，接受後重讀', (t) async {
      be.friends = [peerJson(bId, '小明', timeKey: 'since')];
      be.requests = {
        'incoming': [peerJson(cId, '小華'), peerJson(dId, '')],
        'outgoing': [peerJson('eeeeeeee-0000-0000-0000-000000000005', '小美')],
      };
      final auth = makeAuth();
      await auth.init();
      final s = FriendService(api: be.api, auth: auth);
      await t.pumpWidget(
        MaterialApp(
          home: FriendsPage(service: s, auth: auth),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('好友（1）'), findsOneWidget);
      expect(find.text('收到的邀請（2）'), findsOneWidget);
      expect(find.text('送出的邀請（1）'), findsOneWidget);
      expect(find.text('小明'), findsOneWidget);
      expect(find.text('（未知的域民）'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNWidgets(4)); // 無頭像用預設圖示

      be.override = (r) {
        if (r.method != 'POST') return null;
        be.requests = {
          'incoming': [peerJson(dId, '')],
          'outgoing': be.requests['outgoing']!,
        };
        be.friends = [...be.friends, peerJson(cId, '小華', timeKey: 'since')];
        return jsonResp(peerJson(cId, '小華', timeKey: 'since'));
      };
      await t.tap(find.text('接受').first);
      await t.pumpAndSettle();
      expect(find.text('好友（2）'), findsOneWidget);
      expect(find.text('收到的邀請（1）'), findsOneWidget);
    });

    testWidgets('取消送出的邀請', (t) async {
      be.requests = {
        'incoming': [],
        'outgoing': [peerJson(bId, '小明')],
      };
      final auth = makeAuth();
      await auth.init();
      final s = FriendService(api: be.api, auth: auth);
      await t.pumpWidget(
        MaterialApp(
          home: FriendsPage(service: s, auth: auth),
        ),
      );
      await t.pumpAndSettle();
      be.override = (r) {
        if (r.method != 'DELETE') return null;
        be.requests = {'incoming': [], 'outgoing': []};
        return null;
      };
      await t.tap(find.text('取消邀請'));
      await t.pumpAndSettle();
      expect(find.text('送出的邀請（0）'), findsOneWidget);
      expect(be.calls.any((c) => c.method == 'DELETE'), isTrue);
    });
  });

  group('AddFriendButton', () {
    Future<void> pump(WidgetTester t, FriendService s, {String? ownerId}) =>
        t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  AddFriendButton(
                    token: 'tok',
                    ownerAccountId: ownerId,
                    service: s,
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('有 account_id：已是好友時開頁即顯示，且不可按', (t) async {
      be.friends = [peerJson(bId, 'B', timeKey: 'since')];
      final s = await makeService(t);
      await pump(t, s, ownerId: bId);
      expect(find.text('已是好友'), findsOneWidget);
      expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    });

    testWidgets('有 account_id：已送出邀請時開頁即顯示', (t) async {
      be.requests = {
        'incoming': [],
        'outgoing': [peerJson(bId, 'B')],
      };
      final s = await makeService(t);
      await pump(t, s, ownerId: bId);
      expect(find.text('已送出邀請'), findsOneWidget);
    });

    testWidgets('有 account_id：擁有者是自己', (t) async {
      final s = await makeService(t);
      await pump(t, s, ownerId: meId);
      expect(find.text('這是你自己'), findsOneWidget);
    });

    testWidgets('有 account_id：對方還不是好友，顯示加好友並送出後變已送出', (t) async {
      final s = await makeService(t);
      await pump(t, s, ownerId: bId);
      expect(find.text('加好友'), findsOneWidget);
      be.override = (r) {
        if (r.method != 'POST') return null;
        be.requests = {
          'incoming': [],
          'outgoing': [peerJson(bId, 'B')],
        };
        return jsonResp({'status': 'sent'});
      };
      await t.tap(find.text('加好友'));
      await t.pumpAndSettle();
      expect(find.text('已送出邀請'), findsOneWidget);
      expect(find.text('已送出好友邀請'), findsOneWidget); // SnackBar
    });

    testWidgets('無 account_id（後端未上線）：開頁顯示加好友，按下後依回應', (t) async {
      be.friends = [peerJson(bId, 'B', timeKey: 'since')]; // 即使已是好友也無從得知
      final s = await makeService(t);
      await pump(t, s);
      expect(find.text('加好友'), findsOneWidget);
      be.override = (r) =>
          r.method == 'POST' ? jsonResp({'err': 'already_friends'}, 409) : null;
      await t.tap(find.text('加好友'));
      await t.pumpAndSettle();
      expect(find.text('已是好友'), findsOneWidget);
      expect(find.text('你們已經是好友'), findsOneWidget);
    });

    testWidgets('無 account_id：互送直接成為好友', (t) async {
      final s = await makeService(t);
      await pump(t, s);
      be.override = (r) =>
          r.method == 'POST' ? jsonResp({'status': 'friends'}) : null;
      await t.tap(find.text('加好友'));
      await t.pumpAndSettle();
      expect(find.text('已是好友'), findsOneWidget);
    });

    testWidgets('失敗時顯示錯誤提示且按鈕仍可再按', (t) async {
      final s = await makeService(t);
      await pump(t, s);
      be.override = (r) =>
          r.method == 'POST' ? jsonResp({'err': 'friend_limit'}, 409) : null;
      await t.tap(find.text('加好友'));
      await t.pumpAndSettle();
      expect(find.text('好友已達上限'), findsOneWidget);
      expect(find.text('加好友'), findsOneWidget);
    });
  });

  group('分享清單解析 owner.account_id', () {
    SharedListService svc(Map<String, dynamic> owner) => SharedListService(
      api: makeApi(
        (r) async => jsonResp({'owner': owner, 'entries': <dynamic>[]}),
      ),
      onCopied: () {},
    );

    test('後端有提供：帶出 ownerAccountId', () async {
      final r = await svc({'username': '小明', 'account_id': bId}).fetch('t');
      expect(r.status, CloudSyncStatus.success);
      expect(r.ownerAccountId, bId);
      expect(r.ownerUsername, '小明');
    });

    test('後端尚未提供：ownerAccountId 為 null，其餘照常', () async {
      final r = await svc({'username': '小明'}).fetch('t');
      expect(r.status, CloudSyncStatus.success);
      expect(r.ownerAccountId, isNull);
    });
  });
}
