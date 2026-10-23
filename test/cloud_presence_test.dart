import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/models/cloud_entry.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/cloud_list_service.dart';
import 'package:osu_beatmap_storage/services/cloud_presence_service.dart';
import 'package:osu_beatmap_storage/services/cloud_sync_service.dart';
import 'package:osu_beatmap_storage/widgets/cloud_presence_badge.dart';

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
  ({String sub, String username})? account;
  @override
  Future<({String sub, String username})?> getAccount() async => account;
  @override
  Future<void> setAccount(String? sub, String? username) async =>
      account = sub == null ? null : (sub: sub, username: username ?? '');
  @override
  Future<bool> getForceLogin() async => false;
  @override
  Future<void> setForceLogin(bool value) async {}
}

CloudListResult ok(List<int> ids) => CloudListResult(
  CloudSyncStatus.success,
  entries: [
    for (final id in ids)
      CloudEntry(onlineId: id, dateAdded: DateTime.utc(2024)),
  ],
);

void main() {
  late _Store store;
  late _Prefs prefs;
  late List<CloudListResult> responses;
  late int fetches;

  setUp(() {
    store = _Store();
    prefs = _Prefs();
    responses = [];
    fetches = 0;
  });

  Future<CloudListResult> fetch() async {
    fetches++;
    return responses.isEmpty ? ok([]) : responses.removeAt(0);
  }

  AuthService makeAuth() => AuthService(
    tokenStore: store,
    prefs: prefs,
    httpClient: MockClient((_) async => http.Response('', 200)),
  );

  Future<AuthService> loggedIn() async {
    prefs.account = (sub: 'A', username: 'a');
    store.value = jsonEncode({
      'access': 'a',
      'refresh': 'r',
      'expires_at': DateTime(2099).millisecondsSinceEpoch,
    });
    final auth = makeAuth();
    await auth.init();
    return auth;
  }

  CloudSyncService makeSync() => CloudSyncService(
    api: ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'inserted': 1, 'updated': 0, 'skipped': 0}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      tokenProvider: () async => 'tok',
      refreshToken: (_) async => null,
      onUnauthorized: () async {},
      baseUrl: 'https://api.test',
    ),
  );

  CloudPresenceService make(AuthService auth, [CloudSyncService? sync]) =>
      CloudPresenceService(auth: auth, sync: sync ?? makeSync(), fetch: fetch);

  test('未登入：不讀取，也不算載入', () async {
    final p = make(makeAuth());
    await p.refresh();
    expect(fetches, 0);
    expect(p.loaded, isFalse);
    expect(p.contains(1), isFalse);
  });

  test('登入後自動讀取', () async {
    responses = [
      ok([1, 2]),
    ];
    final p = make(await loggedIn());
    await pumpEventQueue();
    expect(p.loaded, isTrue);
    expect(p.contains(1), isTrue);
    expect(p.contains(3), isFalse);
  });

  test('上傳成功後重讀', () async {
    responses = [
      ok([1]),
      ok([1, 3]),
    ];
    final sync = makeSync();
    final p = make(await loggedIn(), sync);
    await pumpEventQueue();
    await sync.upload([
      CloudEntry(onlineId: 3, dateAdded: DateTime.utc(2024)),
    ], trigger: 'manual');
    await pumpEventQueue();
    expect(fetches, 2);
    expect(p.contains(3), isTrue);
  });

  test('讀取失敗保留上一次的結果', () async {
    responses = [
      ok([1]),
      const CloudListResult(CloudSyncStatus.failed, message: 'x'),
    ];
    final p = make(await loggedIn());
    await pumpEventQueue();
    await p.refresh();
    expect(fetches, 2);
    expect(p.contains(1), isTrue);
  });

  test('讀取中再呼叫：結束後只再讀一次', () async {
    final p = make(await loggedIn());
    await Future.wait([p.refresh(), p.refresh(), p.refresh()]);
    await pumpEventQueue();
    expect(fetches, 2);
  });

  test('讀取中登出再換帳號登入：捨棄舊結果並讀新帳號', () async {
    final gate = Completer<void>();
    var calls = 0;
    final auth = await loggedIn();
    final p = CloudPresenceService(
      auth: auth,
      sync: makeSync(),
      fetch: () async {
        calls++;
        if (calls == 1) {
          await gate.future;
          return ok([1]);
        }
        return ok([2]);
      },
    );
    await pumpEventQueue();
    await auth.logout();
    prefs.account = (sub: 'B', username: 'b');
    store.value = jsonEncode({
      'access': 'b',
      'refresh': 'rb',
      'expires_at': DateTime(2099).millisecondsSinceEpoch,
    });
    // 以還原登入的方式切成 B（不經瀏覽器）
    await auth.init();
    gate.complete();
    await pumpEventQueue();
    expect(calls, 2);
    expect(p.loaded, isTrue);
    expect(p.contains(1), isFalse);
    expect(p.contains(2), isTrue);
  });

  test('上傳失敗也重讀（前面的批次可能已寫入）', () async {
    final sync = CloudSyncService(
      api: ApiClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
        tokenProvider: () async => 'tok',
        refreshToken: (_) async => null,
        onUnauthorized: () async {},
        baseUrl: 'https://api.test',
      ),
    );
    make(await loggedIn(), sync);
    await pumpEventQueue();
    await sync.upload([
      CloudEntry(onlineId: 3, dateAdded: DateTime.utc(2024)),
    ], trigger: 'manual');
    await pumpEventQueue();
    expect(fetches, 2);
  });

  test('登出時清掉', () async {
    responses = [
      ok([1]),
    ];
    final auth = await loggedIn();
    final p = make(auth);
    await pumpEventQueue();
    await auth.logout();
    expect(p.loaded, isFalse);
    expect(p.contains(1), isFalse);
  });

  group('CloudPresenceBadge', () {
    Future<void> pump(WidgetTester t, CloudPresenceService p, int id) =>
        t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CloudPresenceBadge(onlineID: id, service: p),
            ),
          ),
        );

    testWidgets('未載入時什麼都不顯示', (t) async {
      final p = make(makeAuth());
      await pump(t, p, 0);
      expect(find.text('本地圖譜'), findsNothing);
      expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
    });

    testWidgets('在雲端顯示雲朵、不在雲端不顯示、沒有 OnlineID 顯示本地圖譜', (t) async {
      late CloudPresenceService p;
      await t.runAsync(() async {
        responses = [
          ok([1]),
        ];
        p = make(await loggedIn());
        await pumpEventQueue();
      });
      await pump(t, p, 1);
      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      await pump(t, p, 2);
      expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
      expect(find.text('本地圖譜'), findsNothing);
      await pump(t, p, 0);
      expect(find.text('本地圖譜'), findsOneWidget);
    });
  });
}
