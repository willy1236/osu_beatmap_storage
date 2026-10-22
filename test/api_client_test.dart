import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';

void main() {
  late List<http.Request> requests;
  late List<String> refreshed; // 收到的 rejected token
  late int unauthorizedCalls;

  ApiClient make(
    Future<http.Response> Function(http.Request) handler, {
    String? token = 'tok-1',
    String? Function(String rejected)? refresh,
    Duration? timeout,
  }) {
    requests = [];
    refreshed = [];
    unauthorizedCalls = 0;
    return ApiClient(
      httpClient: MockClient((r) {
        requests.add(r);
        return handler(r);
      }),
      tokenProvider: () async => token,
      refreshToken: (rejected) async {
        refreshed.add(rejected);
        return refresh?.call(rejected);
      },
      onUnauthorized: () async => unauthorizedCalls++,
      baseUrl: 'https://api.test',
      timeout: timeout,
    );
  }

  test('帶 Bearer token、JSON body 與 query', () async {
    final api = make((r) async => http.Response('{}', 200));
    final resp = await api.send(
      'POST',
      '/osu/x',
      jsonBody: {'名': 1},
      query: {'a': 'b'},
    );
    expect(resp.statusCode, 200);
    final r = requests.single;
    expect(r.method, 'POST');
    expect(r.url.toString(), 'https://api.test/osu/x?a=b');
    expect(r.headers['Authorization'], 'Bearer tok-1');
    expect(r.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(utf8.decode(r.bodyBytes)), {'名': 1});
  });

  test('GET 沒有 body 也沒有 Content-Type', () async {
    final api = make((r) async => http.Response('{}', 200));
    await api.send('GET', '/osu/beatmaps');
    expect(requests.single.bodyBytes, isEmpty);
    expect(requests.single.headers.containsKey('Content-Type'), isFalse);
  });

  test('沒有 token：丟 NotSignedInException，不送請求', () async {
    final api = make((r) async => http.Response('', 200), token: null);
    await expectLater(
      api.send('GET', '/x'),
      throwsA(isA<NotSignedInException>()),
    );
    expect(requests, isEmpty);
  });

  test('401 → refresh → 用新 token 重送一次並回傳成功', () async {
    final api = make(
      (r) async => http.Response(
        '{}',
        r.headers['Authorization'] == 'Bearer tok-2' ? 200 : 401,
      ),
      refresh: (_) => 'tok-2',
    );
    final resp = await api.send('POST', '/x', jsonBody: {'a': 1});
    expect(resp.statusCode, 200);
    expect(refreshed, ['tok-1']);
    expect(requests.length, 2);
    expect(requests[1].headers['Authorization'], 'Bearer tok-2');
    expect(utf8.decode(requests[1].bodyBytes), '{"a":1}');
    expect(unauthorizedCalls, 0);
  });

  test('新 token 仍 401：回傳 401 並通知 onUnauthorized，只重送一次', () async {
    final api = make(
      (r) async => http.Response('{}', 401),
      refresh: (_) => 'tok-2',
    );
    final resp = await api.send('GET', '/x');
    expect(resp.statusCode, 401);
    expect(requests.length, 2);
    expect(unauthorizedCalls, 1);
  });

  test('refresh 失敗（回 null）：直接回傳原 401，不重送、不標記', () async {
    final api = make((r) async => http.Response('{}', 401));
    final resp = await api.send('GET', '/x');
    expect(resp.statusCode, 401);
    expect(requests.length, 1);
    expect(unauthorizedCalls, 0);
  });

  test('非 401（429、503、500、422）原樣回傳，不 refresh', () async {
    for (final code in [429, 503, 500, 422]) {
      final api = make((r) async => http.Response('{}', code));
      expect((await api.send('GET', '/x')).statusCode, code);
      expect(refreshed, isEmpty);
    }
  });

  test('網路錯誤與逾時直接丟出', () async {
    final down = make((r) async => throw const SocketException('down'));
    await expectLater(down.send('GET', '/x'), throwsA(isA<SocketException>()));
    final slow = make(
      (r) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(slow.send('GET', '/x'), throwsA(isA<TimeoutException>()));
  });
}
