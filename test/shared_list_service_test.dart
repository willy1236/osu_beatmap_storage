import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/cloud_sync_service.dart';
import 'package:osu_beatmap_storage/services/shared_list_service.dart';

void main() {
  late List<http.Request> requests;

  SharedListService make(
    Future<http.Response> Function(http.Request) handler, {
    String? token = 't',
  }) {
    requests = [];
    return SharedListService(
      api: ApiClient(
        httpClient: MockClient((r) {
          requests.add(r);
          return handler(r);
        }),
        tokenProvider: () async => token,
        refreshToken: (_) async => null,
        onUnauthorized: () async {},
        baseUrl: 'https://api.test',
      ),
    );
  }

  http.Response json(Object body, [int code = 200]) => http.Response(
    jsonEncode(body),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, dynamic> entry(int id) => {
    'online_id': id,
    'title': 't$id',
    'date_added': '2026-01-01T00:00:00Z',
  };

  group('fetch', () {
    test('200：解析擁有者代號與清單，打 GET /osu/shared/{token}', () async {
      final s = make(
        (_) async => json({
          'owner': {'username': '小明'},
          'entries': [entry(1), entry(2)],
        }),
      );
      final r = await s.fetch('abc');
      expect(r.ok, isTrue);
      expect(r.ownerUsername, '小明');
      expect(r.entries.map((e) => e.onlineId), [1, 2]);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/osu/shared/abc');
    });

    test('token 會做 URL 編碼', () async {
      final s = make((_) async => json({'owner': {}, 'entries': []}));
      await s.fetch('a/b?c');
      expect(requests.single.url.toString(), contains('/osu/shared/a%2Fb%3Fc'));
    });

    test('擁有者代號為空字串照常回傳', () async {
      final s = make(
        (_) async => json({
          'owner': {'username': ''},
          'entries': [],
        }),
      );
      final r = await s.fetch('abc');
      expect(r.ok, isTrue);
      expect(r.ownerUsername, '');
    });

    test('404 -> 連結已失效', () async {
      final s = make((_) async => json({'err': 'not_found'}, 404));
      final r = await s.fetch('abc');
      expect(r.ok, isFalse);
      expect(r.expired, isTrue);
      expect(r.message, '連結已失效');
    });

    test('401、未登入 -> unauthorized；429、503 對應；其他失敗', () async {
      expect(
        (await make((_) async => json({}, 401)).fetch('a')).status,
        CloudSyncStatus.unauthorized,
      );
      expect(
        (await make((_) async => json({}), token: null).fetch('a')).status,
        CloudSyncStatus.unauthorized,
      );
      expect(
        (await make((_) async => json({}, 429)).fetch('a')).status,
        CloudSyncStatus.rateLimited,
      );
      expect(
        (await make((_) async => json({}, 503)).fetch('a')).status,
        CloudSyncStatus.unavailable,
      );
      for (final h in <Future<http.Response> Function(http.Request)>[
        (_) async => json({}, 500),
        (_) async => throw TimeoutException('t'),
        (_) async => throw Exception('net'),
        (_) async => http.Response('not json', 200),
        (_) async => json({'entries': []}),
      ]) {
        final r = await make(h).fetch('a');
        expect(r.status, CloudSyncStatus.failed);
        expect(r.expired, isFalse);
        expect(r.message, isNotNull);
      }
    });
  });

  group('copyToMine', () {
    test('200：回新增與更新筆數，打 POST /osu/shared/{token}/copy', () async {
      final s = make((_) async => json({'inserted': 3, 'updated': 2}));
      final r = await s.copyToMine('abc');
      expect(r.ok, isTrue);
      expect(r.inserted, 3);
      expect(r.updated, 2);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/osu/shared/abc/copy');
    });

    test('429 -> 請稍後再試', () async {
      final s = make((_) async => json({'err': 'rate_limited'}, 429));
      final r = await s.copyToMine('abc');
      expect(r.status, CloudSyncStatus.rateLimited);
      expect(r.message, '請稍後再試');
    });

    test('404 -> 連結已失效；其他失敗', () async {
      expect(
        (await make((_) async => json({}, 404)).copyToMine('a')).message,
        '連結已失效',
      );
      expect(
        (await make((_) async => json({}, 401)).copyToMine('a')).status,
        CloudSyncStatus.unauthorized,
      );
      expect(
        (await make((_) async => json({}, 503)).copyToMine('a')).status,
        CloudSyncStatus.unavailable,
      );
      for (final h in <Future<http.Response> Function(http.Request)>[
        (_) async => json({}, 500),
        (_) async => throw TimeoutException('t'),
        (_) async => throw Exception('net'),
        (_) async => json({'inserted': 1}),
      ]) {
        expect((await make(h).copyToMine('a')).status, CloudSyncStatus.failed);
      }
    });
  });
}
