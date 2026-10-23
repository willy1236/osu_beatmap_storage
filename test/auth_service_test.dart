import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';

class FakeStore implements AuthTokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;

  @override
  Future<void> delete() async => value = null;
}

class FakePrefs implements AuthPrefs {
  ({String sub, String username})? account;
  bool force = false;

  @override
  Future<({String sub, String username})?> getAccount() async => account;

  @override
  Future<void> setAccount(String? sub, String? username) async =>
      account = sub == null ? null : (sub: sub, username: username ?? '');

  @override
  Future<bool> getForceLogin() async => force;

  @override
  Future<void> setForceLogin(bool value) async => force = value;
}

String jwt(Map<String, dynamic> claims) {
  String enc(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${enc({'alg': 'none'})}.${enc(claims)}.sig';
}

String tokenBody({
  String access = 'access-1',
  String? refresh = 'refresh-1',
  int expiresIn = 3600,
}) => jsonEncode({
  'access_token': access,
  'refresh_token': ?refresh,
  'expires_in': expiresIn,
  'id_token': jwt({'sub': 'acc-1', 'preferred_username': '小明'}),
});

void main() {
  late FakeStore store;
  late FakePrefs prefs;
  late DateTime now;
  late List<http.Request> requests;

  setUp(() {
    store = FakeStore();
    prefs = FakePrefs();
    now = DateTime(2026, 1, 1, 12);
    requests = [];
  });

  AuthService build(
    Future<http.Response> Function(http.Request) handler, {
    Future<bool> Function(Uri)? openBrowser,
    Duration loginTimeout = const Duration(seconds: 5),
  }) => AuthService(
    httpClient: MockClient((req) {
      requests.add(req);
      return handler(req);
    }),
    tokenStore: store,
    prefs: prefs,
    openBrowser: openBrowser ?? (_) async => true,
    now: () => now,
    loginTimeout: loginTimeout,
  );

  /// 模擬瀏覽器：對 redirect_uri 送出指定的 callback 參數
  Future<bool> Function(Uri) browser(
    Map<String, String> Function(Uri authUrl) params, {
    void Function(Uri authUrl)? onOpen,
  }) => (authUrl) async {
    onOpen?.call(authUrl);
    final redirect = Uri.parse(authUrl.queryParameters['redirect_uri']!);
    final q = params(authUrl);
    unawaited(
      (() async {
        final c = HttpClient();
        final r = await (await c.getUrl(
          redirect.replace(queryParameters: q),
        )).close();
        await r.drain<void>();
        c.close();
      })(),
    );
    return true;
  };

  Future<AuthService> loggedIn() async {
    final auth = build(
      (_) async => http.Response(tokenBody(), 200),
      openBrowser: browser((u) => {'code': 'c', 'state': u.queryParameters['state']!}),
    );
    await auth.login();
    expect(auth.status, AuthStatus.loggedIn);
    requests.clear();
    return auth;
  }

  group('login', () {
    test('PKCE、loopback redirect，成功後存 token 與帳號', () async {
      Uri? opened;
      final auth = build(
        (_) async => http.Response(tokenBody(), 200),
        openBrowser: browser(
          (u) => {'code': 'the-code', 'state': u.queryParameters['state']!},
          onOpen: (u) => opened = u,
        ),
      );
      await auth.login();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.sub, 'acc-1');
      expect(auth.username, '小明');
      expect(prefs.account, (sub: 'acc-1', username: '小明'));
      expect(store.value, contains('refresh-1'));
      expect(await auth.accessToken(), 'access-1');

      final q = opened!.queryParameters;
      expect(opened!.origin, 'https://auth.domalyze.net');
      expect(opened!.path, '/oauth2/auth');
      expect(q['client_id'], 'osu-beatmap-storage');
      expect(q['scope'], 'openid offline_access profile');
      expect(q['code_challenge_method'], 'S256');
      expect(q['redirect_uri'], matches(r'^http://127\.0\.0\.1:\d+/callback$'));
      expect(q.containsKey('prompt'), isFalse);

      final body = requests.single.bodyFields;
      expect(body['grant_type'], 'authorization_code');
      expect(body['code'], 'the-code');
      expect(body['redirect_uri'], q['redirect_uri']);
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(body['code_verifier']!)).bytes)
          .replaceAll('=', '');
      expect(challenge, q['code_challenge']);
    });

    test('瀏覽器取消（access_denied）回到未登入', () async {
      final auth = build(
        (_) async => fail('不應呼叫 token endpoint'),
        openBrowser: browser((u) => {
          'error': 'access_denied',
          'state': u.queryParameters['state']!,
        }),
      );
      await auth.login();
      expect(auth.status, AuthStatus.loggedOut);
      expect(auth.lastError, '已取消登入');
      expect(requests, isEmpty);
    });

    test('關掉分頁沒有 callback：逾時後回到未登入，不卡住', () async {
      final auth = build(
        (_) async => fail('不應呼叫 token endpoint'),
        loginTimeout: const Duration(milliseconds: 50),
      );
      await auth.login();
      expect(auth.status, AuthStatus.loggedOut);
      expect(auth.lastError, '登入逾時，請重試');
    });

    test('在程式內按取消', () async {
      late AuthService auth;
      auth = build(
        (_) async => fail('不應呼叫 token endpoint'),
        openBrowser: (_) async {
          Timer(const Duration(milliseconds: 20), () => auth.cancelLogin());
          return true;
        },
      );
      await auth.login();
      expect(auth.status, AuthStatus.loggedOut);
      expect(auth.lastError, isNull);
    });

    test('state 不符時拒絕', () async {
      final auth = build(
        (_) async => fail('不應呼叫 token endpoint'),
        openBrowser: browser((_) => {'code': 'c', 'state': 'forged'}),
      );
      await auth.login();
      expect(auth.status, AuthStatus.loggedOut);
      expect(auth.lastError, startsWith('登入失敗'));
      expect(store.value, isNull);
    });

    test('token endpoint 回錯誤時回到未登入', () async {
      final auth = build(
        (_) async => http.Response('{}', 500),
        openBrowser: browser((u) => {'code': 'c', 'state': u.queryParameters['state']!}),
      );
      await auth.login();
      expect(auth.status, AuthStatus.loggedOut);
      expect(auth.lastError, startsWith('登入失敗'));
      expect(store.value, isNull);
      expect(prefs.account, isNull);
    });

    test('沒拿到 refresh token 視為失敗', () async {
      final auth = build(
        (_) async => http.Response(tokenBody(refresh: null), 200),
        openBrowser: browser((u) => {'code': 'c', 'state': u.queryParameters['state']!}),
      );
      await auth.login();
      expect(auth.status, AuthStatus.loggedOut);
    });
  });

  group('logout', () {
    test('撤銷 refresh token、清除狀態，下次登入帶 prompt=login，登入成功後清掉旗標', () async {
      final auth = await loggedIn();
      await auth.logout();

      expect(auth.status, AuthStatus.loggedOut);
      expect(auth.sub, isNull);
      expect(store.value, isNull);
      expect(prefs.account, isNull);
      expect(prefs.force, isTrue);
      final revoke = requests.single;
      expect(revoke.url.path, '/oauth2/revoke');
      expect(revoke.bodyFields['token'], 'refresh-1');
      expect(revoke.bodyFields['client_id'], 'osu-beatmap-storage');

      Uri? opened;
      final again = build(
        (_) async => http.Response(tokenBody(), 200),
        openBrowser: browser(
          (u) => {'code': 'c', 'state': u.queryParameters['state']!},
          onOpen: (u) => opened = u,
        ),
      );
      await again.login();
      expect(opened!.queryParameters['prompt'], 'login');
      expect(again.isLoggedIn, isTrue);
      expect(prefs.force, isFalse);
    });

    test('撤銷失敗仍會登出', () async {
      final auth = build(
        (_) async => http.Response(tokenBody(), 200),
        openBrowser: browser((u) => {'code': 'c', 'state': u.queryParameters['state']!}),
      );
      await auth.login();
      final failing = AuthService(
        httpClient: MockClient((_) async => throw const SocketException('x')),
        tokenStore: store,
        prefs: prefs,
      );
      await failing.init();
      await failing.logout();
      expect(failing.status, AuthStatus.loggedOut);
      expect(store.value, isNull);
    });
  });

  group('init', () {
    test('重開程式還原登入狀態', () async {
      await (await loggedIn()).accessToken();
      final reopened = build((_) async => fail('不應連線'));
      await reopened.init();
      expect(reopened.isLoggedIn, isTrue);
      expect(reopened.username, '小明');
      expect(await reopened.accessToken(), 'access-1');
    });

    test('只剩其中一邊時當作未登入並清乾淨', () async {
      store.value = '{"access":"a","refresh":"r","expires_at":1}';
      final auth = build((_) async => fail('不應連線'));
      await auth.init();
      expect(auth.status, AuthStatus.loggedOut);
      expect(store.value, isNull);
    });

    test('token 資料損毀時當作未登入', () async {
      store.value = 'not json';
      prefs.account = (sub: 's', username: 'u');
      final auth = build((_) async => fail('不應連線'));
      await auth.init();
      expect(auth.status, AuthStatus.loggedOut);
      expect(prefs.account, isNull);
    });
  });

  group('accessToken', () {
    test('快過期時 refresh，並保存 rotate 後的新 refresh token', () async {
      final auth = await loggedIn();
      now = now.add(const Duration(minutes: 59, seconds: 30));
      final handler = build((req) async {
        return http.Response(
          tokenBody(access: 'access-2', refresh: 'refresh-2'),
          200,
        );
      });
      // 用同一份儲存開新的 service 以換掉 http client
      await handler.init();
      expect(await handler.accessToken(), 'access-2');
      expect(requests.single.bodyFields['grant_type'], 'refresh_token');
      expect(requests.single.bodyFields['refresh_token'], 'refresh-1');
      expect(store.value, contains('refresh-2'));
      expect(auth.isLoggedIn, isTrue);
    });

    test('同時多個呼叫只送一次 refresh', () async {
      await loggedIn();
      now = now.add(const Duration(hours: 2));
      final gate = Completer<void>();
      final auth = build((_) async {
        await gate.future;
        return http.Response(tokenBody(access: 'access-2'), 200);
      });
      await auth.init();
      final results = Future.wait([
        auth.accessToken(),
        auth.accessToken(),
        auth.accessToken(),
      ]);
      gate.complete();
      expect(await results, ['access-2', 'access-2', 'access-2']);
      expect(requests.length, 1);
    });

    test('refresh token 失效（400 invalid_grant）轉成需要重新登入', () async {
      await loggedIn();
      now = now.add(const Duration(hours: 2));
      final auth = build(
        (_) async => http.Response('{"error":"invalid_grant"}', 400),
      );
      await auth.init();
      // init 發現 access token 過期時會在背景 refresh
      await pumpEventQueue();
      expect(auth.status, AuthStatus.reloginRequired);
      expect(await auth.accessToken(), isNull);
      expect(store.value, isNull);
      expect(prefs.account, isNull);
    });

    test('停權（403 access_denied）轉成需要重新登入', () async {
      await loggedIn();
      now = now.add(const Duration(hours: 2));
      final auth = build(
        (_) async => http.Response('{"error":"access_denied"}', 403),
      );
      await auth.init();
      expect(await auth.accessToken(), isNull);
      expect(auth.status, AuthStatus.reloginRequired);
    });

    test('refresh 途中登出：結果作廢，維持未登入、不寫回 token', () async {
      await loggedIn();
      now = now.add(const Duration(hours: 2));
      final gate = Completer<void>();
      final auth = build((req) async {
        if (req.url.path.endsWith('/token')) {
          await gate.future;
          return http.Response(tokenBody(access: 'access-2'), 200);
        }
        return http.Response('', 200);
      });
      await auth.init();
      final pending = auth.accessToken();
      await auth.logout();
      gate.complete();
      expect(await pending, isNull);
      expect(auth.status, AuthStatus.loggedOut);
      expect(store.value, isNull);
    });

    test('撤銷等待期間 refresh 回來：結果作廢並撤銷新的 refresh token，不閃成需要重新登入', () async {
      await loggedIn();
      now = now.add(const Duration(hours: 2));
      final refreshGate = Completer<void>();
      final revokeGate = Completer<void>();
      final revoked = <String>[];
      final auth = build((req) async {
        if (req.url.path.endsWith('/token')) {
          await refreshGate.future;
          return http.Response(
            tokenBody(access: 'access-2', refresh: 'refresh-2'),
            200,
          );
        }
        revoked.add(req.bodyFields['token']!);
        await revokeGate.future;
        return http.Response('', 200);
      });
      await auth.init();
      final statuses = <AuthStatus>[];
      auth.addListener(() => statuses.add(auth.status));
      final pending = auth.accessToken();
      final out = auth.logout();
      await pumpEventQueue();
      refreshGate.complete();
      expect(await pending, isNull);
      await pumpEventQueue();
      revokeGate.complete();
      await out;
      await pumpEventQueue();
      expect(revoked, containsAll(['refresh-1', 'refresh-2']));
      expect(statuses, isNot(contains(AuthStatus.reloginRequired)));
      expect(auth.status, AuthStatus.loggedOut);
      expect(store.value, isNull);
    });

    test('登出後重新登入：不沿用舊 session 進行中的 refresh', () async {
      await loggedIn();
      now = now.add(const Duration(hours: 2));
      final oldGate = Completer<void>();
      var tokenCalls = 0;
      final auth = build(
        (req) async {
          if (req.url.path.endsWith('/token')) {
            tokenCalls++;
            // 第一次是舊 session 的 refresh（卡住），之後是登入與新 session 的 refresh
            if (tokenCalls == 1) {
              await oldGate.future;
              return http.Response(tokenBody(access: 'old-2'), 200);
            }
            return http.Response(
              tokenBody(access: 'access-$tokenCalls'),
              200,
            );
          }
          return http.Response('', 200);
        },
        openBrowser: browser(
          (u) => {'code': 'c', 'state': u.queryParameters['state']!},
        ),
      );
      await auth.init();
      final stale = auth.accessToken();
      await auth.logout();
      await auth.login();
      expect(auth.isLoggedIn, isTrue);
      final fresh = await auth.refreshAccessToken();
      expect(fresh, 'access-3');
      oldGate.complete();
      expect(await stale, isNull);
      expect(await auth.accessToken(), 'access-3');
    });

    test('refreshAccessToken：強制 refresh；rejected 已不是目前 token 時不再送', () async {
      final auth = await loggedIn();
      final a = build(
        (_) async => http.Response(
          tokenBody(access: 'access-2', refresh: 'refresh-2'),
          200,
        ),
      );
      await a.init();
      // token 還沒過期，accessToken() 不會 refresh；強制版會
      expect(await a.accessToken(), 'access-1');
      expect(await a.refreshAccessToken(rejected: 'access-1'), 'access-2');
      expect(requests.length, 1);
      // 另一個呼叫拿著舊的 rejected token：直接回目前的，不再送
      expect(await a.refreshAccessToken(rejected: 'access-1'), 'access-2');
      expect(requests.length, 1);
      expect(auth.isLoggedIn, isTrue);
    });

    test('refreshAccessToken：並發只送一次；失效轉需要重新登入', () async {
      await loggedIn();
      final gate = Completer<void>();
      final a = build((_) async {
        await gate.future;
        return http.Response(tokenBody(access: 'access-2'), 200);
      });
      await a.init();
      final r = Future.wait([
        a.refreshAccessToken(rejected: 'access-1'),
        a.refreshAccessToken(rejected: 'access-1'),
      ]);
      gate.complete();
      expect(await r, ['access-2', 'access-2']);
      expect(requests.length, 1);

      final bad = build(
        (_) async => http.Response('{"error":"invalid_grant"}', 400),
      );
      await bad.init();
      expect(await bad.refreshAccessToken(rejected: 'access-2'), isNull);
      expect(bad.status, AuthStatus.reloginRequired);
      expect(await bad.refreshAccessToken(), isNull);
    });

    test('markReloginRequired：清掉登入資料並轉成需要重新登入', () async {
      final auth = await loggedIn();
      await auth.markReloginRequired();
      expect(auth.status, AuthStatus.reloginRequired);
      expect(store.value, isNull);
      expect(prefs.account, isNull);
      expect(await auth.accessToken(), isNull);
    });

    test('網路錯誤或 5xx 不登出', () async {
      await loggedIn();
      now = now.add(const Duration(hours: 2));
      var offline = true;
      final auth = build((_) async {
        if (offline) throw const SocketException('offline');
        return http.Response(tokenBody(access: 'access-2'), 200);
      });
      await auth.init();
      expect(await auth.accessToken(), isNull);
      expect(auth.isLoggedIn, isTrue);
      expect(store.value, isNotNull);
      offline = false;
      expect(await auth.accessToken(), 'access-2');
    });

    test('未登入時回 null', () async {
      final auth = build((_) async => fail('不應連線'));
      expect(await auth.accessToken(), isNull);
    });
  });
}
