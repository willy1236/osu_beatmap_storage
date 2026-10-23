import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/pages/blocked_page.dart';
import 'package:osu_beatmap_storage/pages/friends_page.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/widgets/block_owner_button.dart';

import 'friend_test_helpers.dart';

void main() {
  late FakeFriendBackend be;
  var blocks = <dynamic>[];

  setUp(() {
    be = FakeFriendBackend();
    blocks = [];
    // 模擬後端：封鎖 = 移除好友與雙方邀請並加入名單；解除封鎖只移除名單
    be.override = (r) {
      final p = r.url.path;
      if (r.method == 'GET' && p == '/social/blocks') {
        return jsonResp({'blocks': blocks});
      }
      final id = p.split('/').last;
      if (r.method == 'PUT' && p.startsWith('/social/blocks/')) {
        be.friends = be.friends.where((e) => e['account_id'] != id).toList();
        be.requests = {
          for (final k in be.requests.keys)
            k: be.requests[k]!.where((e) => e['account_id'] != id).toList(),
        };
        blocks = [...blocks, peerJson(id, 'X')];
        return null;
      }
      if (r.method == 'DELETE' && p.startsWith('/social/blocks/')) {
        blocks = blocks.where((e) => e['account_id'] != id).toList();
        return null;
      }
      if (r.method == 'DELETE' && p.startsWith('/social/friends/')) {
        be.friends = be.friends.where((e) => e['account_id'] != id).toList();
        return null;
      }
      return null;
    };
  });

  Future<(FriendService, AuthService)> make() async {
    final auth = makeAuth();
    await auth.init();
    final s = FriendService(api: be.api, auth: auth);
    await pumpEventQueue();
    return (s, auth);
  }

  group('FriendService', () {
    test('removeFriend：DELETE /social/friends/{id} 後重讀', () async {
      be.friends = [peerJson(bId, 'B', timeKey: 'since')];
      final (s, _) = await make();
      final r = await s.removeFriend(bId);
      expect(r.ok, isTrue);
      expect(
        be.calls.any(
          (c) => c.method == 'DELETE' && c.url.path == '/social/friends/$bId',
        ),
        isTrue,
      );
      expect(s.friends, isEmpty);
    });

    test('block：好友與收到的邀請一併消失；名單已載入時同步更新', () async {
      be.friends = [peerJson(bId, 'B', timeKey: 'since')];
      be.requests = {
        'incoming': [peerJson(cId, 'C')],
        'outgoing': [],
      };
      final (s, _) = await make();
      await s.refreshBlocks();
      expect(s.blocks, isEmpty);
      expect((await s.block(bId)).ok, isTrue);
      expect((await s.block(cId)).ok, isTrue);
      expect(s.friends, isEmpty);
      expect(s.incoming, isEmpty);
      expect(s.blocks.map((e) => e.accountId), [bId, cId]);
    });

    test('block 失敗：回 cannot_block_self 的提示，不更新名單', () async {
      final (s, _) = await make();
      be.override = (r) => r.method == 'PUT'
          ? jsonResp({'err': 'cannot_block_self'}, 422)
          : null;
      final r = await s.block(meId);
      expect(r.ok, isFalse);
      expect(r.code, 'cannot_block_self');
      expect(r.message, '不能封鎖自己');
    });

    test('unblock：移出名單，不恢復好友', () async {
      blocks = [peerJson(bId, 'B')];
      final (s, _) = await make();
      await s.refreshBlocks();
      expect(s.blocks, hasLength(1));
      expect((await s.unblock(bId)).ok, isTrue);
      expect(s.blocks, isEmpty);
      expect(s.friends, isEmpty);
    });

    test('refreshBlocks 失敗：保留上一次名單並設 blocksError', () async {
      blocks = [peerJson(bId, 'B')];
      final (s, _) = await make();
      await s.refreshBlocks();
      final prev = be.override;
      be.override = (r) => jsonResp({'err': 'unavailable'}, 503);
      await s.refreshBlocks();
      expect(s.blocks, hasLength(1));
      expect(s.blocksError, '服務暫時無法使用，請稍後再試');
      be.override = prev;
      await s.refreshBlocks();
      expect(s.blocksError, isNull);
    });

    test('blocked_by_you 提示請先解除封鎖', () async {
      final (s, _) = await make();
      be.override = (r) => r.method == 'POST'
          ? jsonResp({'err': 'blocked_by_you'}, 409)
          : null;
      final r = await s.sendViaShare('tok');
      expect(r.code, 'blocked_by_you');
      expect(r.message, '你已封鎖這位域民，請先到封鎖名單解除封鎖');
    });

    test('換帳號或登出：清空封鎖名單', () async {
      blocks = [peerJson(bId, 'B')];
      final (s, auth) = await make();
      await s.refreshBlocks();
      expect(s.blocksLoaded, isTrue);
      await auth.logout();
      await pumpEventQueue();
      expect(s.blocks, isEmpty);
      expect(s.blocksLoaded, isFalse);
    });
  });

  group('好友頁選單', () {
    Future<FriendService> pumpPage(WidgetTester t) async {
      final auth = makeAuth();
      await auth.init();
      final s = FriendService(api: be.api, auth: auth);
      await t.pumpWidget(
        MaterialApp(
          home: FriendsPage(service: s, auth: auth),
        ),
      );
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('刪除好友：確認後才送出', (t) async {
      be.friends = [peerJson(bId, '小明', timeKey: 'since')];
      await pumpPage(t);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('刪除好友'));
      await t.pumpAndSettle();
      // 取消：不送出
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(be.calls.any((c) => c.method == 'DELETE'), isFalse);

      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('刪除好友'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '刪除'));
      await t.pumpAndSettle();
      expect(find.text('好友（0）'), findsOneWidget);
    });

    testWidgets('收到的邀請：封鎖後邀請移除，且沒有刪除好友選項', (t) async {
      be.requests = {
        'incoming': [peerJson(cId, '小華')],
        'outgoing': [],
      };
      await pumpPage(t);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      expect(find.text('刪除好友'), findsNothing);
      await t.tap(find.text('封鎖'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '封鎖'));
      await t.pumpAndSettle();
      expect(find.text('收到的邀請（0）'), findsOneWidget);
      expect(
        be.calls.any(
          (c) => c.method == 'PUT' && c.url.path == '/social/blocks/$cId',
        ),
        isTrue,
      );
    });

    testWidgets('AppBar 進封鎖名單、解除封鎖', (t) async {
      blocks = [peerJson(bId, '被封鎖的人')];
      await pumpPage(t);
      await t.tap(find.byTooltip('封鎖名單'));
      await t.pumpAndSettle();
      expect(find.byType(BlockedPage), findsOneWidget);
      expect(find.text('被封鎖的人'), findsOneWidget);
      await t.tap(find.text('解除封鎖'));
      await t.pumpAndSettle();
      expect(find.text('被封鎖的人'), findsNothing);
      expect(find.text('沒有封鎖的域民'), findsOneWidget);
    });
  });

  group('BlockOwnerButton', () {
    Future<FriendService> pumpButton(WidgetTester t, String? ownerId) async {
      final auth = makeAuth();
      await auth.init();
      final s = FriendService(api: be.api, auth: auth);
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                BlockOwnerButton(
                  ownerAccountId: ownerId,
                  ownerName: '小明',
                  service: s,
                ),
              ],
            ),
          ),
        ),
      );
      return s;
    }

    testWidgets('確認後封鎖並顯示已封鎖', (t) async {
      await pumpButton(t, bId);
      await t.tap(find.text('封鎖'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(be.calls.any((c) => c.method == 'PUT'), isFalse);

      await t.tap(find.text('封鎖'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '封鎖'));
      await t.pumpAndSettle();
      expect(find.text('已封鎖'), findsOneWidget);
      expect(
        be.calls.any(
          (c) => c.method == 'PUT' && c.url.path == '/social/blocks/$bId',
        ),
        isTrue,
      );
    });

    testWidgets('沒有 account_id 或擁有者是自己：不顯示', (t) async {
      await pumpButton(t, null);
      expect(find.text('封鎖'), findsNothing);
      await pumpButton(t, meId);
      expect(find.text('封鎖'), findsNothing);
    });
  });
}
