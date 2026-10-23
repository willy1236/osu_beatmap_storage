import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/update_service.dart';

String _release(String tag, {List<String> assets = const []}) => jsonEncode({
  'tag_name': tag,
  'body': 'notes',
  'assets': [
    for (final name in assets)
      {'name': name, 'browser_download_url': 'https://example.com/$name'},
  ],
});

UpdateService _service(
  String body, {
  String current = '2.1.0',
  int code = 200,
}) => UpdateService(
  client: MockClient((_) async => http.Response(body, code)),
  currentVersion: current,
  isWindows: true,
);

void main() {
  group('isNewer', () {
    test('比較 x.y.z 數字', () {
      expect(UpdateService.isNewer('2.2.0', '2.1.0'), isTrue);
      expect(UpdateService.isNewer('2.10.0', '2.9.9'), isTrue);
      expect(UpdateService.isNewer('3', '2.9.9'), isTrue);
      expect(UpdateService.isNewer('2.1.0', '2.1.0'), isFalse);
      expect(UpdateService.isNewer('2.0.9', '2.1.0'), isFalse);
    });

    test('忽略 build 與 pre-release 後綴，無法解析視為不新', () {
      expect(UpdateService.isNewer('2.1.0+5', '2.1.0'), isFalse);
      expect(UpdateService.isNewer('2.2.0-beta', '2.1.0'), isTrue);
      expect(UpdateService.isNewer('abc', '2.1.0'), isFalse);
    });
  });

  group('check', () {
    test('有新版且有 zip 時標示可更新', () async {
      final s = _service(
        _release('v2.2.0', assets: ['osu_beatmap_storage_v2.2.0.zip']),
      );
      await s.check();
      expect(s.status, UpdateStatus.available);
      expect(s.available!.version, '2.2.0');
      expect(
        s.available!.zipUrl,
        'https://example.com/osu_beatmap_storage_v2.2.0.zip',
      );
    });

    test('版本相同、沒有 zip 或請求失敗都不提示', () async {
      for (final s in [
        _service(
          _release('v2.1.0', assets: ['osu_beatmap_storage_v2.1.0.zip']),
        ),
        _service(_release('v2.2.0', assets: ['other.zip'])),
        _service('rate limited', code: 403),
        _service('not json'),
      ]) {
        await s.check();
        expect(s.available, isNull);
      }
    });

    test('本機開發版（沒帶 APP_VERSION）不發請求', () async {
      var called = false;
      final s = UpdateService(
        client: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
        currentVersion: '',
        isWindows: true,
      );
      await s.check();
      expect(called, isFalse);
    });
  });
}
