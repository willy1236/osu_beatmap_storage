import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/share_service.dart';
import 'package:osu_beatmap_storage/utils/share_link.dart';
import 'package:osu_beatmap_storage/widgets/share_dialog.dart';

void main() {
  group('share_link', () {
    test('build 與 parse 來回', () {
      expect(buildShareLink('abc-_123'), 'osu-storage://share/abc-_123');
      expect(parseShareLink(buildShareLink('abc-_123')), 'abc-_123');
    });
    test('容許空白、結尾斜線與 scheme 大小寫', () {
      expect(parseShareLink('  OSU-Storage://share/tok/ \n'), 'tok');
    });
    test('格式不符回 null', () {
      for (final s in [
        '',
        'tok',
        'https://share/tok',
        'osu-storage://share/',
        'osu-storage://other/tok',
        'osu-storage://share/a/b',
        'osu-storage://share/a b',
        'osu-storage://share/%zz',
      ]) {
        expect(parseShareLink(s), isNull, reason: s);
      }
    });
  });

  group('ShareService', () {
    late List<http.Request> requests;

    ShareService make(
      Future<http.Response> Function(http.Request) handler, {
      String? token = 't',
    }) {
      requests = [];
      return ShareService(
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
      headers: {'content-type': 'application/json'},
    );

    test('fetch 200 回 token，打 GET /osu/share', () async {
      final s = make(
        (_) async =>
            json({'token': 'abc', 'created_at': '2026-01-01T00:00:00Z'}),
      );
      final r = await s.fetch();
      expect(r.status, ShareStatus.ok);
      expect(r.token, 'abc');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/osu/share');
    });

    test('fetch 404 是 none 不是錯誤', () async {
      final s = make((_) async => json({'err': 'not_found'}, 404));
      expect((await s.fetch()).status, ShareStatus.none);
    });

    test('regenerate 打 POST 並回新 token', () async {
      final s = make((_) async => json({'token': 'new', 'created_at': 'x'}));
      final r = await s.regenerate();
      expect(r.token, 'new');
      expect(requests.single.method, 'POST');
    });

    test('revoke 204 成功，打 DELETE', () async {
      final s = make((_) async => http.Response('', 204));
      final r = await s.revoke();
      expect(r.ok, isTrue);
      expect(r.token, isNull);
      expect(requests.single.method, 'DELETE');
    });

    test('POST／DELETE 的 404 算失敗', () async {
      final s = make((_) async => json({}, 404));
      expect((await s.regenerate()).status, ShareStatus.failed);
    });

    test('401、未登入 -> unauthorized', () async {
      expect(
        (await make((_) async => json({}, 401)).fetch()).status,
        ShareStatus.unauthorized,
      );
      expect(
        (await make((_) async => json({}), token: null).fetch()).status,
        ShareStatus.unauthorized,
      );
    });

    test('503、5xx、逾時、網路錯誤、格式錯誤 -> failed', () async {
      for (final h in <Future<http.Response> Function(http.Request)>[
        (_) async => json({}, 503),
        (_) async => json({}, 500),
        (_) async => throw TimeoutException('t'),
        (_) async => throw Exception('net'),
        (_) async => http.Response('not json', 200),
        (_) async => json({'token': ''}),
      ]) {
        final r = await make(h).fetch();
        expect(r.status, ShareStatus.failed);
        expect(r.message, isNotNull);
      }
    });
  });

  group('ShareDialog', () {
    Future<void> pump(WidgetTester t, ShareService s) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShareDialog(service: s)),
        ),
      );
      await t.pumpAndSettle();
    }

    ShareService svc(List<String> calls, {String? initial}) {
      var token = initial;
      var n = 0;
      return ShareService(
        api: ApiClient(
          httpClient: MockClient((r) async {
            calls.add(r.method);
            switch (r.method) {
              case 'GET':
                return token == null
                    ? http.Response('{}', 404)
                    : http.Response('{"token":"$token"}', 200);
              case 'POST':
                token = 'tok${++n}';
                return http.Response('{"token":"$token"}', 200);
              default:
                token = null;
                return http.Response('', 204);
            }
          }),
          tokenProvider: () async => 't',
          refreshToken: (_) async => null,
          onUnauthorized: () async {},
          baseUrl: 'https://api.test',
        ),
      );
    }

    testWidgets('沒有連結 -> 產生；再重新產生要確認，取消不呼叫 POST', (t) async {
      final calls = <String>[];
      await pump(t, svc(calls));
      expect(find.text('產生連結'), findsOneWidget);

      await t.tap(find.text('產生連結'));
      await t.pumpAndSettle();
      expect(find.text('osu-storage://share/tok1'), findsOneWidget);

      await t.tap(find.text('重新產生'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(calls, ['GET', 'POST']);
      expect(find.text('osu-storage://share/tok1'), findsOneWidget);

      await t.tap(find.text('重新產生'));
      await t.pumpAndSettle();
      await t.tap(find.text('確定'));
      await t.pumpAndSettle();
      expect(find.text('osu-storage://share/tok2'), findsOneWidget);
    });

    testWidgets('讀取失敗時只提供重試，不提供產生連結', (t) async {
      final calls = <String>[];
      var fail = true;
      final s = ShareService(
        api: ApiClient(
          httpClient: MockClient((r) async {
            calls.add(r.method);
            return fail
                ? http.Response('', 503)
                : http.Response('{"token":"tok1"}', 200);
          }),
          tokenProvider: () async => 't',
          refreshToken: (_) async => null,
          onUnauthorized: () async {},
          baseUrl: 'https://api.test',
        ),
      );
      await pump(t, s);
      expect(find.text('產生連結'), findsNothing);
      expect(find.text('重試'), findsOneWidget);

      fail = false;
      await t.tap(find.text('重試'));
      await t.pumpAndSettle();
      expect(calls, ['GET', 'GET']);
      expect(find.text('osu-storage://share/tok1'), findsOneWidget);
    });

    testWidgets('撤銷要確認，成功後回到沒有連結', (t) async {
      final calls = <String>[];
      await pump(t, svc(calls, initial: 'abc'));
      expect(find.text('osu-storage://share/abc'), findsOneWidget);

      await t.tap(find.text('撤銷'));
      await t.pumpAndSettle();
      expect(calls, ['GET']);
      await t.tap(find.text('確定'));
      await t.pumpAndSettle();
      expect(calls, ['GET', 'DELETE']);
      expect(find.text('產生連結'), findsOneWidget);
    });

    testWidgets('複製會寫入剪貼簿', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await pump(t, svc([], initial: 'abc'));
      await t.tap(find.text('複製'));
      await t.pumpAndSettle();
      expect(copied, 'osu-storage://share/abc');
      expect(find.text('已複製到剪貼簿'), findsOneWidget);
    });
  });
}
