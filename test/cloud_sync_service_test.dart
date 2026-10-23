import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/models/cloud_entry.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/cloud_sync_service.dart';

List<CloudEntry> entries(int n, {int startId = 1}) => [
  for (var i = 0; i < n; i++)
    CloudEntry(onlineId: startId + i, dateAdded: DateTime.utc(2024)),
];

http.Response json(int code, Object body, {Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json', ...?headers},
    );

void main() {
  late DateTime clock;
  late int idCounter;
  late List<http.Request> requests;

  CloudSyncService make(
    Future<http.Response> Function(http.Request) handler, {
    Future<String?> Function()? token,
    Duration? timeout,
  }) {
    requests = [];
    return CloudSyncService(
      api: ApiClient(
        httpClient: MockClient((r) {
          requests.add(r);
          return handler(r);
        }),
        tokenProvider: token ?? () async => 'tok',
        refreshToken: (_) async => null,
        onUnauthorized: () async {},
        baseUrl: 'https://api.test',
        timeout: timeout,
      ),
      now: () => clock,
      newSyncId: () => 'sync-${++idCounter}',
    );
  }

  Map<String, dynamic> body(http.Request r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  setUp(() {
    clock = DateTime(2026, 1, 1, 12);
    idCounter = 0;
  });

  test('成功：路徑、header、body、分批與共用 sync_id、進度、結果加總', () async {
    final progress = <int>[];
    final svc = make(
      (r) async => json(200, {'inserted': 1000, 'updated': 0, 'skipped': 0}),
    );
    svc.addListener(() {
      final p = svc.progress;
      if (p != null) progress.add(p.sent);
    });
    final result = await svc.upload(entries(2500), trigger: 'manual');

    expect(result.status, CloudSyncStatus.success);
    expect(result.inserted, 3000); // mock 每批回 1000
    expect(requests.length, 3);
    expect(requests.map((r) => body(r)['entries'].length).toList(), [
      1000,
      1000,
      500,
    ]);
    for (final r in requests) {
      expect(r.url.toString(), 'https://api.test/osu/beatmaps/merge');
      expect(r.headers['Authorization'], 'Bearer tok');
      expect(body(r)['trigger'], 'manual');
      expect(body(r)['sync_id'], 'sync-1');
    }
    expect(progress, containsAllInOrder([0, 1000, 2000, 2500]));
    expect(svc.progress, isNull);
    expect(svc.lastError, isNull);
    expect(svc.uploading, isFalse);
  });

  test('OnlineID ≤ 0 在本機略過並計入 skipped', () async {
    final svc = make(
      (r) async => json(200, {'inserted': 1, 'updated': 0, 'skipped': 0}),
    );
    final list = [...entries(1), ...entries(2, startId: -1)];
    final result = await svc.upload(list, trigger: 'manual');
    expect(body(requests.single)['entries'].length, 1);
    expect(result.skipped, 2);
  });

  test('全部都被略過時不呼叫後端', () async {
    final svc = make((r) async => json(200, {}));
    final result = await svc.upload(entries(1, startId: 0), trigger: 'manual');
    expect(result.ok, isTrue);
    expect(requests, isEmpty);
  });

  test('429：標為被頻率限制擋下，帶 Retry-After，不算錯誤', () async {
    final svc = make(
      (r) async =>
          json(429, {'err': 'rate_limited'}, headers: {'retry-after': '42'}),
    );
    final result = await svc.upload(entries(3), trigger: 'manual');
    expect(result.status, CloudSyncStatus.rateLimited);
    expect(result.retryAfter, 42);
    expect(svc.lastError, isNull);
  });

  test('503 unavailable：暫時失敗並記錄錯誤', () async {
    final svc = make((r) async => json(503, {'err': 'unavailable'}));
    final result = await svc.upload(entries(3), trigger: 'auto');
    expect(result.status, CloudSyncStatus.unavailable);
    expect(svc.lastError, isNotNull);
  });

  test('401 與 token 為 null：unauthorized', () async {
    final a = make((r) async => json(401, {'err': 'unauthorized'}));
    expect(
      (await a.upload(entries(1), trigger: 'manual')).status,
      CloudSyncStatus.unauthorized,
    );
    final b = make((r) async => json(200, {}), token: () async => null);
    expect(
      (await b.upload(entries(1), trigger: 'manual')).status,
      CloudSyncStatus.unauthorized,
    );
    expect(requests, isEmpty);
  });

  test('422、5xx、網路錯誤、逾時、壞回應：failed 並設 lastError', () async {
    for (final handler in <Future<http.Response> Function(http.Request)>[
      (r) async => json(422, {'err': 'invalid_request', 'description': 'bad'}),
      (r) async => json(500, {'err': 'internal_error'}),
      (r) async => throw const SocketException('down'),
      (r) async => http.Response('not json', 200),
    ]) {
      final svc = make(handler);
      final result = await svc.upload(entries(1), trigger: 'manual');
      expect(result.status, CloudSyncStatus.failed);
      expect(svc.lastError, isNotNull);
    }
    final slow = make(
      (r) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 20),
    );
    final result = await slow.upload(entries(1), trigger: 'manual');
    expect(result.status, CloudSyncStatus.failed);
    expect(slow.lastError, contains('逾時'));
  });

  test('同時只有一次上傳：第二次回 busy', () async {
    final gate = Completer<http.Response>();
    final svc = make((r) => gate.future);
    final first = svc.upload(entries(1), trigger: 'manual');
    final second = await svc.upload(entries(1), trigger: 'manual');
    expect(second.status, CloudSyncStatus.busy);
    gate.complete(json(200, {'inserted': 1, 'updated': 0, 'skipped': 0}));
    expect((await first).ok, isTrue);
  });

  test('失敗後 10 分鐘內重試沿用 sync_id，超過或換 trigger 則換新的', () async {
    var fail = true;
    final svc = make(
      (r) async => fail
          ? json(500, {'err': 'internal_error'})
          : json(200, {'inserted': 1, 'updated': 0, 'skipped': 0}),
    );
    await svc.upload(entries(1), trigger: 'manual');
    clock = clock.add(const Duration(minutes: 2));
    await svc.upload(entries(1), trigger: 'manual');
    expect(requests.map((r) => body(r)['sync_id']), ['sync-1', 'sync-1']);

    await svc.upload(entries(1), trigger: 'csv');
    expect(body(requests.last)['sync_id'], 'sync-2');

    clock = clock.add(const Duration(minutes: 11));
    await svc.upload(entries(1), trigger: 'csv');
    expect(body(requests.last)['sync_id'], 'sync-3');

    // 成功後下一次是新的同步，不能沿用（否則會繞過頻率限制）
    fail = false;
    await svc.upload(entries(1), trigger: 'csv');
    expect(body(requests.last)['sync_id'], 'sync-3');
    await svc.upload(entries(1), trigger: 'csv');
    expect(body(requests.last)['sync_id'], 'sync-4');
  });

  test('429 後下一次使用新的 sync_id', () async {
    var limited = true;
    final svc = make(
      (r) async => limited
          ? json(429, {'err': 'rate_limited'}, headers: {'retry-after': '5'})
          : json(200, {'inserted': 0, 'updated': 0, 'skipped': 0}),
    );
    await svc.upload(entries(1), trigger: 'manual');
    limited = false;
    await svc.upload(entries(1), trigger: 'manual');
    expect(requests.map((r) => body(r)['sync_id']), ['sync-1', 'sync-2']);
  });
}
