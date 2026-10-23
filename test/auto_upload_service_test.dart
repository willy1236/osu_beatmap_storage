import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/models/cloud_entry.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/auto_upload_service.dart';
import 'package:osu_beatmap_storage/services/cloud_sync_service.dart';

class _Store implements AuthTokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

class _Prefs implements AuthPrefs {
  ({String sub, String username, String? picture})? account;
  @override
  Future<({String sub, String username, String? picture})?>
  getAccount() async => account;
  @override
  Future<void> setAccount(
    String? sub,
    String? username, {
    String? picture,
  }) async => account = sub == null
      ? null
      : (sub: sub, username: username ?? '', picture: picture);
  @override
  Future<bool> getForceLogin() async => false;
  @override
  Future<void> setForceLogin(bool value) async {}
}

String _tokens() => jsonEncode({
  'access': 'a',
  'refresh': 'r',
  'expires_at': DateTime(2099).millisecondsSinceEpoch,
});

void main() {
  late _Store store;
  late _Prefs prefs;
  late List<http.Request> requests;
  late http.Response Function(http.Request) handler;
  String? saved;
  var writes = 0;

  AuthService makeAuth() => AuthService(tokenStore: store, prefs: prefs);

  CloudSyncService makeSync() => CloudSyncService(
    api: ApiClient(
      httpClient: MockClient((r) async {
        requests.add(r);
        return handler(r);
      }),
      tokenProvider: () async => 'tok',
      refreshToken: (_) async => null,
      onUnauthorized: () async {},
      baseUrl: 'https://api.test',
    ),
  );

  AutoUploadService makeAuto(AuthService auth) => AutoUploadService(
    auth: auth,
    sync: makeSync(),
    readSub: () async => saved,
    writeSub: (s) async {
      saved = s;
      writes++;
    },
  );

  List<CloudEntry> entries() => [
    CloudEntry(onlineId: 1, dateAdded: DateTime.utc(2024)),
  ];

  http.Response ok() => http.Response(
    jsonEncode({'inserted': 1, 'updated': 0, 'skipped': 0}),
    200,
    headers: {'content-type': 'application/json'},
  );

  setUp(() {
    store = _Store();
    prefs = _Prefs();
    requests = [];
    saved = null;
    writes = 0;
    handler = (_) => ok();
  });

  /// 還原成指定帳號已登入的 AuthService（沿用 AuthService 的存檔格式）
  Future<AuthService> loggedInAs(String sub) async {
    prefs.account = (sub: sub, username: 'u-$sub', picture: null);
    store.value = _tokens();
    final auth = makeAuth();
    await auth.init();
    return auth;
  }

  test('ready：init 結束後完成，即使沒有登入資料', () async {
    final auth = makeAuth();
    var done = false;
    auth.ready.then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    await auth.init();
    await auth.ready;
    expect(auth.isLoggedIn, isFalse);
  });

  test('預設關閉：已登入但沒有設定時不上傳', () async {
    final auth = await loggedInAs('A');
    expect(auth.isLoggedIn, isTrue, reason: '測試前提：token 存檔格式要能還原');
    final auto = makeAuto(auth);
    expect(await auto.runOnStartup(entries), isNull);
    expect(auto.enabled, isFalse);
    expect(requests, isEmpty);
  });

  test('開啟後：程式開啟時以 trigger=auto 上傳', () async {
    final auth = await loggedInAs('A');
    final auto = makeAuto(auth);
    await auto.setEnabled(true);
    expect(auto.enabled, isTrue);
    expect(saved, 'A');

    final r = await auto.runOnStartup(entries);
    expect(r!.status, CloudSyncStatus.success);
    expect(requests, hasLength(1));
    final body =
        jsonDecode(utf8.decode(requests.single.bodyBytes))
            as Map<String, dynamic>;
    expect(body['trigger'], 'auto');
  });

  test('換帳號自動關閉；登出再登回同一人維持開啟', () async {
    saved = 'A';
    final b = makeAuto(await loggedInAs('B'));
    await b.load();
    expect(b.enabled, isFalse);
    expect(await b.runOnStartup(entries), isNull);
    expect(requests, isEmpty);

    final a = makeAuto(await loggedInAs('A'));
    await a.load();
    expect(a.enabled, isTrue);
  });

  test('未登入：靜默跳過，不呼叫後端', () async {
    saved = 'A';
    final auth = makeAuth();
    await auth.init();
    final auto = makeAuto(auth);
    expect(await auto.runOnStartup(entries), isNull);
    expect(requests, isEmpty);
  });

  test('429：回 rateLimited，且不設定 lastError', () async {
    saved = 'A';
    handler = (_) => http.Response(
      '{}',
      429,
      headers: {'content-type': 'application/json', 'retry-after': '60'},
    );
    final auth = await loggedInAs('A');
    final auto = makeAuto(auth);
    final r = await auto.runOnStartup(entries);
    expect(r!.status, CloudSyncStatus.rateLimited);
  });

  test('關閉：清除設定', () async {
    saved = 'A';
    final auto = makeAuto(await loggedInAs('A'));
    await auto.setEnabled(false);
    expect(saved, isNull);
    expect(auto.enabled, isFalse);
  });

  test('toggle：尚未 load 時依設定檔的狀態取反', () async {
    saved = 'A';
    final auto = makeAuto(await loggedInAs('A'));
    await auto.toggle();
    expect(saved, isNull);
    expect(auto.enabled, isFalse);
  });

  test('未登入時 setEnabled 不寫入', () async {
    final auto = makeAuto(makeAuth());
    await auto.setEnabled(true);
    expect(writes, 0);
  });
}
