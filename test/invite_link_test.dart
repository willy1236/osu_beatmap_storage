import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:osu_beatmap_storage/services/app_link_service.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/friend_link_opener.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/invite_link_service.dart';
import 'package:osu_beatmap_storage/utils/friend_link.dart';
import 'package:osu_beatmap_storage/widgets/invite_links_section.dart';
import 'package:osu_beatmap_storage/widgets/open_share_link_dialog.dart';

import 'friend_test_helpers.dart';

/// 假的邀請連結後端：[links] 為自己未使用的連結，[owners] 為別人的連結（token → 擁有者 id）
class _FakeInviteBackend {
  final calls = <String>[];
  List<Map<String, dynamic>> links = [];
  Map<String, String> owners = {};
  int counter = 0;

  /// 設定後，下一次列表 GET 先取好當下的資料，等 gate 完成才回應（模擬在途的舊回應）
  Completer<void>? gate;
  http.Response? Function(http.Request r)? override;

  Future<http.Response> handle(http.Request r) async {
    calls.add('${r.method} ${r.url.path}');
    final o = override?.call(r);
    if (o != null) return o;
    final path = r.url.path;
    if (path == '/social/invite-links') {
      if (r.method == 'GET') {
        final snapshot = jsonResp({'links': links});
        final g = gate;
        gate = null;
        if (g != null) await g.future;
        return snapshot;
      }
      if (links.length >= 20) {
        return jsonResp({'err': 'invite_link_limit'}, 409);
      }
      final l = {
        'token': 'new${++counter}',
        'created_at': '2026-10-23T08:30:00Z',
      };
      links = [l, ...links];
      return jsonResp(l);
    }
    final m = RegExp(
      r'^/social/invite-links/([^/]+)(/accept)?$',
    ).firstMatch(path);
    if (m != null) {
      final token = m.group(1)!;
      if (r.method == 'DELETE') {
        links = [
          for (final l in links)
            if (l['token'] != token) l,
        ];
        return http.Response('', 204);
      }
      final owner = owners[token];
      if (owner == null) return jsonResp({'err': 'not_found'}, 404);
      if (m.group(2) == null) return jsonResp(peerJson(owner, '小明'));
      owners.remove(token);
      return jsonResp(peerJson(owner, '小明', timeKey: 'since'));
    }
    return http.Response('', 204);
  }
}

void main() {
  group('friend link 解析', () {
    test('build 與 parse 互逆，容許空白、結尾斜線與大小寫 scheme', () {
      expect(buildFriendLink('a b'), 'osu-storage://friend/a%20b');
      expect(parseFriendLink(buildFriendLink('a b')), 'a b');
      expect(parseFriendLink('  OSU-STORAGE://friend/abc/ '), 'abc');
    });

    test('格式不符回 null，分享連結不算好友連結', () {
      for (final s in [
        '',
        'osu-storage://friend/',
        'osu-storage://friend/a/b',
        'osu-storage://share/abc',
        'https://x/friend/abc',
      ]) {
        expect(parseFriendLink(s), isNull, reason: s);
      }
    });
  });

  group('InviteLinkService', () {
    late _FakeInviteBackend be;
    late AuthService auth;
    late int friendRefreshes;
    late InviteLinkService s;

    setUp(() async {
      be = _FakeInviteBackend();
      auth = makeAuth();
      await auth.init();
      friendRefreshes = 0;
      s = InviteLinkService(
        api: makeApi(be.handle),
        auth: auth,
        refreshFriends: () async => friendRefreshes++,
      );
    });

    test('讀取中 create：在途舊回應之後再讀一次，列表含新連結', () async {
      be.gate = Completer<void>();
      final gate = be.gate!;
      final first = s.refresh(); // 舊回應：空列表
      final created = s.create();
      await pumpEventQueue();
      gate.complete();
      await Future.wait([first, created]);
      expect(s.links.map((l) => l.token), ['new1']);
      expect(s.loading, isFalse);
    });

    test('create 回 token 並重讀列表，revoke 只移除該條', () async {
      final a = await s.create();
      final b = await s.create();
      expect(a.token, 'new1');
      expect(b.token, 'new2');
      expect(s.links.map((l) => l.token), ['new2', 'new1']);
      expect(s.links.first.createdAt, isNotNull);

      expect((await s.revoke('new1')).ok, isTrue);
      expect(s.links.map((l) => l.token), ['new2']);
    });

    test('第 21 條回 invite_link_limit 說明', () async {
      be.links = [
        for (var i = 0; i < kMaxInviteLinks; i++)
          {'token': 't$i', 'created_at': '2026-10-23T08:30:00Z'},
      ];
      final r = await s.create();
      expect(r.ok, isFalse);
      expect(r.code, 'invite_link_limit');
      expect(r.message, contains('最多 20 條'));
    });

    test('preview 不重讀好友；accept 之後重讀好友，連結失效回「邀請連結已失效」', () async {
      be.owners['tok'] = bId;
      final p = await s.preview('tok');
      expect(p.owner?.accountId, bId);
      expect(p.owner?.displayName, '小明');
      expect(friendRefreshes, 0);

      expect((await s.accept('tok')).ok, isTrue);
      expect(friendRefreshes, 1);

      final again = await s.accept('tok');
      expect(again.ok, isFalse);
      expect(again.message, '邀請連結已失效');
      expect((await s.preview('tok')).message, '邀請連結已失效');
    });

    test('accept 的錯誤碼對應提示', () async {
      be.owners['tok'] = bId;
      for (final (status, code, text) in [
        (422, 'cannot_friend_self', '不能使用自己的邀請連結'),
        (409, 'already_friends', '你們已經是好友'),
        (409, 'friend_limit', '好友已達上限'),
        (409, 'blocked_by_you', '你已封鎖這位域民，請先到封鎖名單解除封鎖'),
      ]) {
        be.override = (_) => jsonResp({'err': code}, status);
        final r = await s.accept('tok');
        expect(r.code, code);
        expect(r.message, text);
      }
    });

    test('換帳號時清空列表', () async {
      be.links = [
        {'token': 't', 'created_at': '2026-10-23T08:30:00Z'},
      ];
      await s.refresh();
      expect(s.links, hasLength(1));
      await auth.logout();
      expect(s.links, isEmpty);
      expect(s.loaded, isFalse);
    });
  });

  group('FriendLinkOpener', () {
    late GlobalKey<NavigatorState> navKey;
    late _FakeInviteBackend be;
    late _FakeAuth fakeAuth;
    late InviteLinkService service;
    late int friendRefreshes;
    FriendRelation relation = FriendRelation.none;
    String? self = meId;

    FriendLinkOpener makeOpener() => FriendLinkOpener(
      navigatorKey: navKey,
      authChanges: fakeAuth,
      isLoggedIn: () => fakeAuth.isLoggedIn,
      authStatus: () => fakeAuth.status,
      login: fakeAuth.login,
      service: service,
      selfId: () => self,
      relationOf: (_) => relation,
    );

    Future<void> pumpApp(WidgetTester t, {bool loggedIn = true}) async {
      navKey = GlobalKey<NavigatorState>();
      be = _FakeInviteBackend()..owners['tok'] = bId;
      fakeAuth = _FakeAuth()
        ..status = loggedIn ? AuthStatus.loggedIn : AuthStatus.loggedOut;
      friendRefreshes = 0;
      relation = FriendRelation.none;
      self = meId;
      final auth = makeAuth();
      await auth.init();
      service = InviteLinkService(
        api: makeApi(be.handle),
        auth: auth,
        refreshFriends: () async => friendRefreshes++,
      );
      await t.pumpWidget(
        MaterialApp(navigatorKey: navKey, home: const Scaffold()),
      );
    }

    Future<void> settle(WidgetTester t) async {
      await t.runAsync(pumpEventQueue);
      await t.pumpAndSettle();
    }

    testWidgets('navigator 還沒掛上時回 false', (t) async {
      await pumpApp(t);
      final o = FriendLinkOpener(
        navigatorKey: GlobalKey<NavigatorState>(),
        authChanges: fakeAuth,
        isLoggedIn: () => true,
        service: service,
      );
      expect(await o.open('tok'), isFalse);
    });

    testWidgets('確認後才 accept：問「要和 小明 成為好友嗎」，成功後重讀好友', (t) async {
      await pumpApp(t);
      unawaited(makeOpener().open('tok'));
      await settle(t);
      expect(find.text('要和 小明 成為好友嗎？'), findsOneWidget);
      expect(be.calls, ['GET /social/invite-links/tok']);

      await t.tap(find.text('成為好友'));
      await settle(t);
      await settle(t);
      expect(be.calls.last, 'POST /social/invite-links/tok/accept');
      expect(find.text('你和 小明 已成為好友'), findsOneWidget);
      expect(friendRefreshes, 1);
    });

    testWidgets('取消確認不呼叫 accept，連結仍有效', (t) async {
      await pumpApp(t);
      unawaited(makeOpener().open('tok'));
      await settle(t);
      await t.tap(find.text('取消'));
      await settle(t);
      expect(be.calls.any((c) => c.endsWith('/accept')), isFalse);
      expect(be.owners.containsKey('tok'), isTrue);
    });

    testWidgets('連結失效：顯示「邀請連結已失效」', (t) async {
      await pumpApp(t);
      be.owners.clear();
      unawaited(makeOpener().open('tok'));
      await settle(t);
      await settle(t);
      expect(find.text('邀請連結已失效'), findsOneWidget);
    });

    testWidgets('自己的連結、已是好友：確認前先提示，不呼叫 accept', (t) async {
      await pumpApp(t);
      self = bId;
      unawaited(makeOpener().open('tok'));
      await settle(t);
      await settle(t);
      expect(find.textContaining('自己的邀請連結'), findsOneWidget);
      await t.tap(find.text('好'));
      await settle(t);

      self = meId;
      relation = FriendRelation.friends;
      unawaited(makeOpener().open('tok'));
      await settle(t);
      await settle(t);
      expect(find.text('你和 小明 已經是好友'), findsOneWidget);
      expect(be.calls.any((c) => c.endsWith('/accept')), isFalse);
    });

    testWidgets('好友已達上限：顯示「好友已達上限」', (t) async {
      await pumpApp(t);
      be.override = (r) => r.url.path.endsWith('/accept')
          ? jsonResp({'err': 'friend_limit'}, 409)
          : null;
      unawaited(makeOpener().open('tok'));
      await settle(t);
      await t.tap(find.text('成為好友'));
      await settle(t);
      await settle(t);
      expect(find.text('好友已達上限'), findsOneWidget);
    });

    testWidgets('未登入：提示登入，登入成功後繼續', (t) async {
      await pumpApp(t, loggedIn: false);
      final o = makeOpener();
      unawaited(o.open('tok'));
      await settle(t);
      expect(find.text('需要先登入'), findsOneWidget);
      expect(o.pendingToken, 'tok');
      await t.tap(find.text('登入'));
      await settle(t);
      expect(fakeAuth.logins, 1);
      expect(be.calls, isEmpty);

      fakeAuth.set(AuthStatus.loggedIn);
      await settle(t);
      expect(find.text('要和 小明 成為好友嗎？'), findsOneWidget);
      expect(o.pendingToken, isNull);
    });

    testWidgets('未登入：取消登入不暫存', (t) async {
      await pumpApp(t, loggedIn: false);
      final o = makeOpener();
      unawaited(o.open('tok'));
      await settle(t);
      await t.tap(find.text('取消'));
      await settle(t);
      expect(o.pendingToken, isNull);
      expect(fakeAuth.logins, 0);
    });
  });

  group('AppLinkService 分派', () {
    AppLinkService make(List<String> shared, List<String> friend) =>
        AppLinkService(
          links: const Stream.empty(),
          ready: () async {},
          open: (t) async {
            shared.add(t);
            return true;
          },
          openFriend: (t) async {
            friend.add(t);
            return true;
          },
        );

    test('friend/ 交給好友開啟器，share/ 仍交給分享開啟器', () async {
      final shared = <String>[], friend = <String>[];
      final s = make(shared, friend);
      expect(await s.handle('osu-storage://friend/abc'), isTrue);
      expect(await s.handle('osu-storage://share/xyz'), isTrue);
      expect(friend, ['abc']);
      expect(shared, ['xyz']);
    });

    test('未知 host 忽略', () async {
      final shared = <String>[], friend = <String>[];
      expect(
        await make(shared, friend).handle('osu-storage://other/a'),
        isFalse,
      );
      expect(shared, isEmpty);
      expect(friend, isEmpty);
    });

    test('navigator 未就緒時重試好友開啟器', () async {
      var n = 0;
      final s = AppLinkService(
        links: const Stream.empty(),
        ready: () async {},
        openFriend: (_) async => ++n >= 3,
        nextFrame: () async {},
      );
      expect(await s.handle('osu-storage://friend/abc'), isTrue);
      expect(n, 3);
    });
  });

  group('OpenShareLinkDialog', () {
    Future<void> pumpDialog(
      WidgetTester t,
      List<String> shared,
      List<String> friend,
    ) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenShareLinkDialog(
            opener: (tk) async {
              shared.add(tk);
              return true;
            },
            friendOpener: (tk) async {
              friend.add(tk);
              return true;
            },
          ),
        ),
      ),
    );

    testWidgets('貼上 friend/ 連結交給好友開啟器', (t) async {
      final shared = <String>[], friend = <String>[];
      await pumpDialog(t, shared, friend);
      expect(find.text('開啟連結'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'osu-storage://friend/abc');
      await t.tap(find.text('開啟'));
      await t.pumpAndSettle();
      expect(friend, ['abc']);
      expect(shared, isEmpty);
    });

    testWidgets('貼上 share/ 連結仍交給分享開啟器；格式不符顯示錯誤', (t) async {
      final shared = <String>[], friend = <String>[];
      await pumpDialog(t, shared, friend);
      await t.enterText(find.byType(TextField), 'nope');
      await t.tap(find.text('開啟'));
      await t.pumpAndSettle();
      expect(find.textContaining('連結格式不正確'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'osu-storage://share/xyz');
      await t.tap(find.text('開啟'));
      await t.pumpAndSettle();
      expect(shared, ['xyz']);
      expect(friend, isEmpty);
    });
  });

  group('InviteLinksSection', () {
    late _FakeInviteBackend be;
    late InviteLinkService service;
    String? clip;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      clip = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clip = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });

    Future<void> pumpSection(WidgetTester t) async {
      be = _FakeInviteBackend();
      final auth = makeAuth();
      await auth.init();
      service = InviteLinkService(
        api: makeApi(be.handle),
        auth: auth,
        refreshFriends: () async {},
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InviteLinksSection(service: service)),
        ),
      );
      await t.runAsync(pumpEventQueue);
      await t.pumpAndSettle();
    }

    testWidgets('產生連結並複製，列表多一條；撤銷後少一條', (t) async {
      await pumpSection(t);
      expect(find.text('邀請連結（0/20）'), findsOneWidget);
      expect(find.text('沒有未使用的邀請連結'), findsOneWidget);

      await t.tap(find.text('產生並複製連結'));
      await t.runAsync(pumpEventQueue);
      await t.pumpAndSettle();
      expect(clip, 'osu-storage://friend/new1');
      expect(find.text('邀請連結（1/20）'), findsOneWidget);
      expect(find.textContaining('產生於 20'), findsOneWidget);

      await t.tap(find.text('撤銷'));
      await t.runAsync(pumpEventQueue);
      await t.pumpAndSettle();
      expect(find.text('邀請連結（0/20）'), findsOneWidget);
      expect(be.links, isEmpty);
    });

    testWidgets('達 20 條時停用產生並提示', (t) async {
      be = _FakeInviteBackend();
      be.links = [
        for (var i = 0; i < kMaxInviteLinks; i++)
          {'token': 't$i', 'created_at': '2026-10-23T08:30:00Z'},
      ];
      final auth = makeAuth();
      await auth.init();
      service = InviteLinkService(
        api: makeApi(be.handle),
        auth: auth,
        refreshFriends: () async {},
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InviteLinksSection(service: service),
            ),
          ),
        ),
      );
      await t.runAsync(pumpEventQueue);
      await t.pumpAndSettle();
      expect(find.text('邀請連結（20/20）'), findsOneWidget);
      expect(find.textContaining('已達上限 20 條'), findsOneWidget);
      final btn = t.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('產生並複製連結'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(btn.onPressed, isNull);
    });
  });
}

class _FakeAuth extends ChangeNotifier {
  AuthStatus status = AuthStatus.loggedOut;
  int logins = 0;
  bool get isLoggedIn => status == AuthStatus.loggedIn;
  Future<void> login() async {
    logins++;
    set(AuthStatus.loggingIn);
  }

  void set(AuthStatus s) {
    status = s;
    notifyListeners();
  }
}
