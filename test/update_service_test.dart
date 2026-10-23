import 'dart:convert';
import 'dart:io';

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
  _applyScriptTests();
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

void _applyScriptTests() {
  group('applyScriptArgs', () {
    test('路徑原樣放進獨立元素，不自行加引號', () {
      final args = UpdateService.applyScriptArgs(
        script: r'C:/Users/A B/Temp/a.ps1',
        appPid: 42,
        source: r'C:/x %TEMP% & ^ (1)/files',
        target: r'D:/App Dir',
        exe: 'app.exe',
        started: r'C:/Users/A B/Temp/started.flag',
      );
      expect(args[args.indexOf('-File') + 1], r'C:/Users/A B/Temp/a.ps1');
      expect(args[args.indexOf('-AppPid') + 1], '42');
      expect(args[args.indexOf('-Source') + 1], r'C:/x %TEMP% & ^ (1)/files');
      expect(args[args.indexOf('-Target') + 1], r'D:/App Dir');
      expect(
        args[args.indexOf('-Started') + 1],
        r'C:/Users/A B/Temp/started.flag',
      );
    });
  });

  group('launchApplyScript', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('upd_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('標記出現就回傳 true', () async {
      final flag = File('${dir.path}/started.flag');
      final ok = await UpdateService.launchApplyScript(
        start: () async {
          Future<void>.delayed(
            const Duration(milliseconds: 50),
            () => flag.writeAsStringSync('started'),
          );
          return await Process.start('cmd', ['/c', 'exit']);
        },
        started: flag,
        timeout: const Duration(seconds: 5),
        interval: const Duration(milliseconds: 10),
      );
      expect(ok, isTrue);
    }, skip: !Platform.isWindows);

    test('逾時沒有標記回傳 false', () async {
      final ok = await UpdateService.launchApplyScript(
        start: () => Process.start('cmd', ['/c', 'exit']),
        started: File('${dir.path}/started.flag'),
        timeout: const Duration(milliseconds: 200),
        interval: const Duration(milliseconds: 10),
      );
      expect(ok, isFalse);
    }, skip: !Platform.isWindows);

    test('啟動丟例外回傳 false', () async {
      final ok = await UpdateService.launchApplyScript(
        start: () async => throw const ProcessException('x', []),
        started: File('${dir.path}/started.flag'),
        timeout: const Duration(milliseconds: 200),
      );
      expect(ok, isFalse);
    });
  });

  test(
    '真實腳本：路徑含空格與 % 也能啟動並完成替換',
    () async {
      final root = Directory.systemTemp.createTempSync('upd real');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } on FileSystemException {
          // 剛啟動的程序可能還鎖著資料夾，留給系統清理
        }
      });
      final base = '${root.path}/a b %TEMP% & ^ (x)';
      final source = Directory('$base/src')..createSync(recursive: true);
      final target = Directory('$base/app')..createSync(recursive: true);
      File('${source.path}/new.dll').writeAsStringSync('new');
      // 用會立刻結束的真實 exe 當作「新版執行檔」
      File(
        '${Platform.environment['SystemRoot']}/System32/hostname.exe',
      ).copySync('${source.path}/run.exe');
      File('${target.path}/old.dll').writeAsStringSync('old');
      final script = File('$base/apply.ps1')
        ..writeAsStringSync(UpdateService.applyScriptSource);
      final started = File('$base/started.flag');

      final ok = await UpdateService.launchApplyScript(
        start: () => Process.start(
          'powershell',
          UpdateService.applyScriptArgs(
            script: script.path,
            appPid: 999999, // 不存在的程序，Wait-Process 立即略過
            source: source.path,
            target: target.path,
            exe: 'run.exe',
            started: started.path,
          ),
        ),
        started: started,
        timeout: const Duration(seconds: 30),
      );
      expect(ok, isTrue);
      // 標記出現時腳本還在跑，等替換完成（Source 被清掉是最後一步）
      for (var i = 0; i < 150 && source.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(File('${target.path}/new.dll').existsSync(), isTrue);
      expect(File('${target.path}/old.dll').existsSync(), isFalse);
      expect(File('${target.path}/run.exe').existsSync(), isTrue);
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
