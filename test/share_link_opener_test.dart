import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/pages/cloud_list_page.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/local_library_service.dart';
import 'package:osu_beatmap_storage/services/share_link_opener.dart';
import 'package:osu_beatmap_storage/services/shared_list_service.dart';
import 'package:osu_beatmap_storage/widgets/open_share_link_dialog.dart';

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

void main() {
  late GlobalKey<NavigatorState> navKey;
  late _FakeAuth auth;
  late LocalLibraryService library;
  late List<String> fetched;

  ShareLinkOpener makeOpener() => ShareLinkOpener(
    navigatorKey: navKey,
    authChanges: auth,
    isLoggedIn: () => auth.isLoggedIn,
    authStatus: () => auth.status,
    login: auth.login,
    library: library,
    service: SharedListService(
      api: ApiClient(
        httpClient: MockClient((r) async {
          fetched.add(r.url.path);
          return http.Response(
            jsonEncode({
              'owner': {'username': '小明'},
              'entries': [
                {'online_id': 1, 'date_added': '2026-01-01T00:00:00Z'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        tokenProvider: () async => 't',
        refreshToken: (_) async => null,
        onUnauthorized: () async {},
        baseUrl: 'https://api.test',
      ),
    ),
  );

  Future<void> pumpApp(WidgetTester t) async {
    navKey = GlobalKey<NavigatorState>();
    auth = _FakeAuth();
    library = LocalLibraryService()..setOnlineIds({1});
    fetched = [];
    await t.pumpWidget(
      MaterialApp(navigatorKey: navKey, home: const Scaffold()),
    );
  }

  testWidgets('navigator 還沒掛上時回 false', (t) async {
    final o = ShareLinkOpener(
      navigatorKey: GlobalKey<NavigatorState>(),
      authChanges: _FakeAuth(),
      isLoggedIn: () => true,
      authStatus: () => AuthStatus.loggedIn,
      login: () async {},
    );
    expect(await o.open('abc'), isFalse);
  });

  testWidgets('已登入：直接開啟 CloudListPage 並讀取該 token', (t) async {
    await pumpApp(t);
    auth.status = AuthStatus.loggedIn;
    final o = makeOpener();
    await t.runAsync(() => o.open('abc'));
    await t.pumpAndSettle();
    expect(find.byType(CloudListPage), findsOneWidget);
    expect(fetched, ['/osu/shared/abc']);
  });

  testWidgets('未登入：提示登入，取消則不暫存也不開頁', (t) async {
    await pumpApp(t);
    final o = makeOpener();
    final f = o.open('abc');
    await t.pumpAndSettle();
    expect(find.text('需要先登入'), findsOneWidget);
    expect(o.pendingToken, 'abc');
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    await f;
    expect(o.pendingToken, isNull);
    expect(auth.logins, 0);
    expect(find.byType(CloudListPage), findsNothing);
  });

  testWidgets('未登入：按登入，登入成功後自動開啟', (t) async {
    await pumpApp(t);
    final o = makeOpener();
    final f = o.open('abc');
    await t.pumpAndSettle();
    await t.tap(find.text('登入'));
    await t.pumpAndSettle();
    await f;
    expect(auth.logins, 1);
    expect(find.byType(CloudListPage), findsNothing);

    auth.set(AuthStatus.loggedIn);
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pumpAndSettle();
    expect(find.byType(CloudListPage), findsOneWidget);
    expect(fetched, ['/osu/shared/abc']);
    expect(o.pendingToken, isNull);
  });

  testWidgets('登入被取消後不再自動開啟', (t) async {
    await pumpApp(t);
    final o = makeOpener();
    final f = o.open('abc');
    await t.pumpAndSettle();
    await t.tap(find.text('登入'));
    await t.pumpAndSettle();
    await f;
    auth.set(AuthStatus.loggedOut);
    expect(o.pendingToken, isNull);
    auth.set(AuthStatus.loggedIn);
    await t.pumpAndSettle();
    expect(find.byType(CloudListPage), findsNothing);
  });

  testWidgets('本機清單未載入：詢問，取消不開頁', (t) async {
    await pumpApp(t);
    auth.status = AuthStatus.loggedIn;
    library = LocalLibraryService();
    final o = makeOpener();
    final f = o.open('abc');
    await t.pumpAndSettle();
    expect(find.text('尚未載入本機圖譜'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    await f;
    expect(find.byType(CloudListPage), findsNothing);
    expect(fetched, isEmpty);
  });

  group('OpenShareLinkDialog', () {
    testWidgets('格式錯誤顯示錯誤，不呼叫 opener；正確則傳出 token', (t) async {
      final tokens = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpenShareLinkDialog(
              opener: (tok) async {
                tokens.add(tok);
                return true;
              },
            ),
          ),
        ),
      );
      await t.enterText(find.byType(TextField), 'hello');
      await t.tap(find.text('開啟'));
      await t.pumpAndSettle();
      expect(find.textContaining('連結格式不正確'), findsOneWidget);
      expect(tokens, isEmpty);

      await t.enterText(find.byType(TextField), ' osu-storage://share/tok1 ');
      await t.tap(find.text('開啟'));
      await t.pumpAndSettle();
      expect(tokens, ['tok1']);
    });
  });
}
