import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';

import 'friend_test_helpers.dart';

void main() {
  late FakeFriendBackend be;

  setUp(() => be = FakeFriendBackend());

  Future<(FriendService, AuthService)> make({bool loggedIn = true}) async {
    final auth = makeAuth(loggedIn: loggedIn);
    await auth.init();
    final s = FriendService(api: be.api, auth: auth);
    await pumpEventQueue();
    return (s, auth);
  }

  test('未登入：不讀取', () async {
    final (s, _) = await make(loggedIn: false);
    await s.refresh();
    expect(be.calls, isEmpty);
    expect(s.loaded, isFalse);
  });

  test('登入後自動讀取好友與邀請，含頭像與空代號退化', () async {
    be.friends = [
      peerJson(bId, '小明', timeKey: 'since', picture: 'https://x/p.png'),
    ];
    be.requests = {
      'incoming': [peerJson(cId, '')],
      'outgoing': [peerJson(dId, 'z')],
    };
    final (s, _) = await make();
    expect(s.loaded, isTrue);
    expect(s.friends.single.username, '小明');
    expect(s.friends.single.picture, 'https://x/p.png');
    expect(s.incoming.single.displayName, '（未知的域民）');
    expect(s.incoming.single.picture, isNull);
    expect(s.outgoing.single.username, 'z');
  });

  test('讀取失敗保留上一次結果並設 error，成功後清除', () async {
    be.friends = [peerJson(bId, 'B', timeKey: 'since')];
    final (s, _) = await make();
    be.override = (r) => jsonResp({'err': 'unavailable'}, 503);
    await s.refresh();
    expect(s.friends, hasLength(1));
    expect(s.error, '服務暫時無法使用，請稍後再試');
    be.override = null;
    await s.refresh();
    expect(s.error, isNull);
  });

  test('relationOf：自己、好友、送出、收到、無關', () async {
    be.friends = [peerJson(bId, 'B', timeKey: 'since')];
    be.requests = {
      'incoming': [peerJson(cId, 'C')],
      'outgoing': [peerJson(dId, 'D')],
    };
    final (s, _) = await make();
    expect(s.relationOf(meId.toUpperCase()), FriendRelation.self);
    expect(s.relationOf(bId), FriendRelation.friends);
    expect(s.relationOf(cId), FriendRelation.incoming);
    expect(s.relationOf(dId), FriendRelation.outgoing);
    expect(
      s.relationOf('eeeeeeee-0000-0000-0000-000000000005'),
      FriendRelation.none,
    );
  });

  test('sendViaShare：送出後重讀（不樂觀更新），回 sent', () async {
    final (s, _) = await make();
    be.calls.clear();
    be.override = (r) {
      if (r.method != 'POST') return null;
      be.requests = {
        'incoming': [],
        'outgoing': [peerJson(bId, 'B')],
      };
      return jsonResp({'status': 'sent'});
    };
    final r = await s.sendViaShare('tok/1');
    expect(r.status, FriendActionStatus.sent);
    expect(be.calls.first.url.path, '/osu/shared/tok%2F1/friend-request');
    expect(be.calls.first.method, 'POST');
    expect(
      be.calls.skip(1).map((c) => c.url.path),
      containsAll(['/social/friends', '/social/requests']),
    );
    expect(s.outgoing.single.accountId, bId);
  });

  test('被對方封鎖時後端回假的 sent：列表以重讀為準，不會多出邀請', () async {
    final (s, _) = await make();
    be.override = (r) =>
        r.method == 'POST' ? jsonResp({'status': 'sent'}) : null;
    final r = await s.sendViaShare('t');
    expect(r.status, FriendActionStatus.sent);
    expect(s.outgoing, isEmpty);
  });

  test('互送：回 friends 並重讀好友', () async {
    final (s, _) = await make();
    be.override = (r) {
      if (r.method != 'POST') return null;
      be.friends = [peerJson(bId, 'B', timeKey: 'since')];
      return jsonResp({'status': 'friends'});
    };
    final r = await s.sendViaShare('t');
    expect(r.status, FriendActionStatus.friends);
    expect(s.friends.single.accountId, bId);
  });

  group('錯誤碼對應', () {
    Future<FriendActionResult> failWith(
      int status,
      Object body, {
      bool accept = false,
    }) async {
      final (s, _) = await make();
      be.override = (r) => r.method == 'POST' ? jsonResp(body, status) : null;
      return accept ? s.accept(bId) : s.sendViaShare('t');
    }

    for (final c in [
      (409, 'already_friends', '你們已經是好友'),
      (409, 'friend_limit', '好友已達上限'),
      (422, 'cannot_friend_self', '不能對自己送邀請'),
      (429, 'rate_limited', '今天送出的邀請太多，請稍後再試'),
      (409, 'blocked_by_you', '你已封鎖這位域民，請先到封鎖名單解除封鎖'),
      (404, 'not_found', '分享連結已失效'),
      (503, 'unavailable', '服務暫時無法使用，請稍後再試'),
      (401, 'unauthorized', '登入已失效，請重新登入'),
    ]) {
      test('送出 ${c.$1} ${c.$2}', () async {
        final r = await failWith(c.$1, {'err': c.$2});
        expect(r.ok, isFalse);
        expect(r.code, c.$2);
        expect(r.message, c.$3);
      });
    }

    test('接受時 friend_limit 與 not_found', () async {
      var r = await failWith(409, {'err': 'friend_limit'}, accept: true);
      expect(r.message, '好友已達上限');
      r = await failWith(404, {'err': 'not_found'}, accept: true);
      expect(r.message, '這筆邀請已不存在');
    });

    test('沒有 err 欄位時依 HTTP 狀態判斷（429）', () async {
      final r = await failWith(429, <String, dynamic>{});
      expect(r.code, 'rate_limited');
    });

    test('失敗後仍重讀列表', () async {
      final (s, _) = await make();
      be.calls.clear();
      be.override = (r) =>
          r.method == 'POST' ? jsonResp({'err': 'not_found'}, 404) : null;
      await s.accept(bId);
      expect(be.calls.map((c) => c.url.path), contains('/social/friends'));
    });
  });

  test('接受、拒絕、取消呼叫正確端點', () async {
    final (s, _) = await make();
    be.calls.clear();
    be.override = (r) => r.url.path.endsWith('/accept')
        ? jsonResp(peerJson(bId, 'B', timeKey: 'since'))
        : null;
    expect((await s.accept(bId)).status, FriendActionStatus.friends);
    expect((await s.reject(bId)).status, FriendActionStatus.done);
    expect((await s.cancel(cId)).status, FriendActionStatus.done);
    final acts = be.calls
        .where((c) => c.url.path.startsWith('/social/requests/'))
        .map((c) => '${c.method} ${c.url.path}')
        .toList();
    expect(acts, [
      'POST /social/requests/$bId/accept',
      'POST /social/requests/$bId/reject',
      'DELETE /social/requests/$cId',
    ]);
  });

  test('登出時清空列表', () async {
    be.friends = [peerJson(bId, 'B', timeKey: 'since')];
    final (s, auth) = await make();
    expect(s.friends, hasLength(1));
    await auth.logout();
    await pumpEventQueue();
    expect(s.friends, isEmpty);
    expect(s.loaded, isFalse);
  });
}
