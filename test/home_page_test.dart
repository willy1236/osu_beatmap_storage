import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/pages/friends_page.dart';
import 'package:osu_beatmap_storage/pages/home_page.dart';
import 'package:osu_beatmap_storage/pages/inbox_page.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/notification_service.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';
import 'package:osu_beatmap_storage/services/realtime_service.dart';
import 'package:osu_beatmap_storage/services/toast_platform.dart';
import 'package:osu_beatmap_storage/widgets/count_badge.dart';
import 'package:osu_beatmap_storage/widgets/peer_avatar.dart';

import 'friend_test_helpers.dart';

class _NoToast implements ToastPlatform {
  @override
  Future<void> show({
    required String title,
    required String body,
    required VoidCallback onClick,
  }) async {}
}

typedef _Home = ({
  NotificationService n,
  FriendService f,
  PushService p,
  AuthService a,
});

void main() {
  late FakeFriendBackend be;

  setUp(() {
    be = FakeFriendBackend();
    be.requests = {
      'incoming': [peerJson(bId, '小明'), peerJson(cId, '小華')],
      'outgoing': [],
    };
    be.override = (r) {
      if (r.method == 'GET' && r.url.path == '/osu/pushes') {
        return jsonResp({
          'pushes': [
            {
              'id': 'p1',
              'from': {'account_id': bId, 'username': '小明', 'picture': null},
              'message': '',
              'entries': <Map<String, dynamic>>[],
              'created_at': '2026-10-02T00:00:00Z',
              'read': false,
            },
          ],
        });
      }
      return null;
    };
  });

  Future<AuthService> makeAuthWith({String? picture}) async {
    final store = MemStore()
      ..value = jsonEncode({
        'access': 'a',
        'refresh': 'r',
        'expires_at': DateTime(2099).millisecondsSinceEpoch,
      });
    final prefs = MemPrefs()
      ..account = (sub: meId, username: '威立', picture: picture);
    final auth = AuthService(
      tokenStore: store,
      prefs: prefs,
      httpClient: MockClient((_) async => http.Response('', 200)),
    );
    await auth.init();
    return auth;
  }

  Future<_Home> pumpHome(WidgetTester t, {String? picture}) async {
    final auth = await makeAuthWith(picture: picture);
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
      toast: _NoToast(),
      restoreWindow: () async {},
    );
    addTearDown(() {
      n.dispose();
      rt.dispose();
      p.dispose();
      f.dispose();
    });
    await t.runAsync(pumpEventQueue); // 登入後的第一次讀取（不依賴真實時間）
    await t.pumpWidget(
      MaterialApp(
        home: HomePage(
          auth: auth,
          notifications: n,
          friends: f,
          beatmapPage: const Placeholder(),
          friendsPage: FriendsPage(
            service: f,
            auth: auth,
            push: p,
            intent: n.intent,
          ),
        ),
      ),
    );
    await t.pump();
    return (n: n, f: f, p: p, a: auth);
  }

  int friendGets() => be.calls
      .where((c) => c.method == 'GET' && c.url.path == '/social/friends')
      .length;

  CircleAvatar avatar(WidgetTester t) => t.widget<CircleAvatar>(
    find.descendant(
      of: find.byType(PeerAvatar),
      matching: find.byType(CircleAvatar),
    ),
  );

  testWidgets('側欄好友入口紅點：收到的邀請數加未讀推送數', (t) async {
    await pumpHome(t);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.descendant(
          of: find.byType(CountBadge),
          matching: find.text('3'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('帳號頭像：沒有 picture 用預設圖示', (t) async {
    await pumpHome(t);
    expect(avatar(t).backgroundImage, isNull);
    expect(
      find.descendant(
        of: find.byType(PeerAvatar),
        matching: find.byIcon(Icons.person),
      ),
      findsOneWidget,
    );
  });

  testWidgets('帳號頭像：有 picture 時使用該網址', (t) async {
    await pumpHome(t, picture: 'https://img.test/me.png');
    expect(
      (avatar(t).backgroundImage! as NetworkImage).url,
      'https://img.test/me.png',
    );
  });

  testWidgets('帳號選單標題列顯示代號，rail 上不顯示', (t) async {
    await pumpHome(t);
    expect(find.text('威立'), findsNothing);
    await t.tap(find.byTooltip('帳號選單'));
    await t.pumpAndSettle();
    expect(find.text('威立'), findsOneWidget);
    expect(find.text('登出'), findsOneWidget);
  });

  testWidgets('每次切到好友頁都重讀好友列表（頁面常駐，不靠 initState）', (t) async {
    await pumpHome(t);
    final before = friendGets();
    await t.tap(find.text('圖譜查看'));
    await t.pump();
    expect(friendGets(), before); // 切到別頁不重讀
    await t.tap(find.text('好友'));
    await t.pump();
    await t.runAsync(pumpEventQueue);
    expect(friendGets(), before + 1);
    await t.tap(find.text('圖譜查看'));
    await t.pump();
    await t.tap(find.text('好友'));
    await t.pump();
    await t.runAsync(pumpEventQueue);
    expect(friendGets(), before + 2);
  });

  testWidgets('點通知（intent）切到好友頁時也重讀', (t) async {
    final s = await pumpHome(t);
    final before = friendGets();
    s.n.intent.value = NotificationTarget.invites;
    await t.pump();
    await t.runAsync(pumpEventQueue);
    expect(friendGets(), before + 1);
  });

  testWidgets('點通知時上面疊著別的 route：先回到首頁層，收件匣只開一個', (t) async {
    final s = await pumpHome(t);
    final nav = Navigator.of(t.element(find.byType(HomePage)));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('蓋住首頁的頁面')),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('蓋住首頁的頁面'), findsOneWidget);

    s.n.intent.value = NotificationTarget.inbox;
    await t.pumpAndSettle();
    expect(find.text('蓋住首頁的頁面'), findsNothing);
    expect(find.byType(InboxPage), findsOneWidget);
    expect(s.n.intent.value, isNull);

    // 收件匣已開著時又來一個推送通知：不重複疊
    s.n.intent.value = NotificationTarget.inbox;
    await t.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
    nav.pop();
    await t.pumpAndSettle();
    expect(find.byType(InboxPage), findsNothing);
  });

  testWidgets('點通知時開著對話框：只還原視窗，不 pop、不切頁、不重讀', (t) async {
    final s = await pumpHome(t);
    showDialog<void>(
      context: t.element(find.byType(HomePage)),
      builder: (_) => const AlertDialog(title: Text('設定中')),
    );
    await t.pumpAndSettle();
    final before = friendGets();
    for (final target in NotificationTarget.values) {
      s.n.intent.value = target;
      await t.pumpAndSettle();
      expect(find.text('設定中'), findsOneWidget);
      expect(find.byType(InboxPage), findsNothing);
      expect(s.n.intent.value, isNull);
    }
    await t.runAsync(pumpEventQueue);
    expect(friendGets(), before);
    final rail = t.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, 0);
  });

  testWidgets('對話框關掉後再點通知：照常切到好友頁', (t) async {
    final s = await pumpHome(t);
    showDialog<void>(
      context: t.element(find.byType(HomePage)),
      builder: (_) => const AlertDialog(title: Text('設定中')),
    );
    await t.pumpAndSettle();
    Navigator.of(t.element(find.byType(HomePage))).pop();
    await t.pumpAndSettle();
    s.n.intent.value = NotificationTarget.inbox;
    await t.pumpAndSettle();
    expect(
      t
          .widget<NavigationRail>(
            find.byType(NavigationRail, skipOffstage: false),
          )
          .selectedIndex,
      2,
    );
    expect(find.byType(InboxPage), findsOneWidget);
  });
}
