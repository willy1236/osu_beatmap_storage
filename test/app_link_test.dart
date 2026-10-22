import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/app_link_service.dart';
import 'package:osu_beatmap_storage/services/protocol_registrar.dart';

void main() {
  group('ProtocolRegistrar（注入假 runner，不碰真實登錄檔）', () {
    const exe = r'D:\app dir\osu_beatmap_storage.exe';
    late List<List<String>> calls;

    ProtocolRegistrar make({
      required ProcessResult Function(List<String> args) handler,
      bool isWindows = true,
      String path = exe,
    }) {
      calls = [];
      return ProtocolRegistrar(
        exePath: path,
        isWindows: isWindows,
        run: (args) async {
          calls.add(args);
          return handler(args);
        },
      );
    }

    ProcessResult res(int code, [String out = '']) =>
        ProcessResult(0, code, out, '');

    test('command 為 "<exe>" "%1"', () {
      expect(make(handler: (_) => res(0)).command, '"$exe" "%1"');
    });

    test('登錄值已是目前路徑（忽略大小寫）：只查詢不寫入', () async {
      final r = make(
        handler: (_) =>
            res(0, '    (預設值)    REG_SZ    "${exe.toUpperCase()}" "%1"'),
      );
      expect(await r.registerIfNeeded(), isFalse);
      expect(calls.length, 1);
      expect(calls.single.first, 'query');
    });

    test('沒有登錄值：寫入三個值，路徑帶在 command', () async {
      final r = make(handler: (a) => a.first == 'query' ? res(1) : res(0));
      expect(await r.registerIfNeeded(), isTrue);
      expect(calls.map((c) => c.first), ['query', 'add', 'add', 'add']);
      expect(calls[1], [
        'add',
        r'HKCU\Software\Classes\osu-storage',
        '/ve',
        '/d',
        'URL:osu-storage',
        '/f',
      ]);
      expect(calls[2], contains('URL Protocol'));
      expect(
        calls[3][1],
        r'HKCU\Software\Classes\osu-storage\shell\open\command',
      );
      expect(calls[3], contains('"$exe" "%1"'));
      // 只動 HKCU\Software\Classes\osu-storage
      for (final c in calls) {
        expect(c[1], startsWith(r'HKCU\Software\Classes\osu-storage'));
      }
    });

    test('搬移後路徑不同：重新寫入', () async {
      final r = make(
        handler: (a) =>
            a.first == 'query' ? res(0, r'REG_SZ "C:\old\x.exe" "%1"') : res(0),
      );
      expect(await r.registerIfNeeded(), isTrue);
      expect(calls.where((c) => c.first == 'add').length, 3);
    });

    test('寫入失敗或丟例外：回 false 且不丟出', () async {
      final fail = make(handler: (a) => a.first == 'query' ? res(1) : res(1));
      expect(await fail.registerIfNeeded(), isFalse);

      final boom = ProtocolRegistrar(
        exePath: exe,
        isWindows: true,
        run: (_) async => throw const ProcessException('reg', []),
      );
      expect(await boom.registerIfNeeded(), isFalse);
    });

    test('非 Windows：什麼都不做', () async {
      final r = make(handler: (_) => res(0), isWindows: false);
      expect(await r.registerIfNeeded(), isFalse);
      expect(calls, isEmpty);
    });
  });

  group('AppLinkService', () {
    test('非分享連結被忽略，不等待 ready 也不開啟', () async {
      final opened = <String>[];
      final s = AppLinkService(
        links: const Stream.empty(),
        ready: () async => fail('不該等待'),
        open: (t) async {
          opened.add(t);
          return true;
        },
      );
      for (final l in ['https://x.com/a', 'osu-storage://other/a', '']) {
        expect(await s.handle(l), isFalse);
      }
      expect(opened, isEmpty);
    });

    test('先等 ready 才開啟', () async {
      final ready = Completer<void>();
      final order = <String>[];
      final s = AppLinkService(
        links: const Stream.empty(),
        ready: () async {
          await ready.future;
          order.add('ready');
        },
        open: (t) async {
          order.add('open:$t');
          return true;
        },
      );
      final f = s.handle('osu-storage://share/abc');
      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);
      ready.complete();
      expect(await f, isTrue);
      expect(order, ['ready', 'open:abc']);
    });

    test('navigator 未掛上（open 回 false）時等下一個 frame 重試', () async {
      var attempts = 0, frames = 0;
      final s = AppLinkService(
        links: const Stream.empty(),
        ready: () async {},
        nextFrame: () async => frames++,
        open: (t) async => ++attempts >= 3,
      );
      expect(await s.handle('osu-storage://share/abc'), isTrue);
      expect(attempts, 3);
      expect(frames, 2);
    });

    test('一直無法開啟時達上限後放棄', () async {
      var attempts = 0;
      final s = AppLinkService(
        links: const Stream.empty(),
        ready: () async {},
        nextFrame: () async {},
        maxAttempts: 5,
        open: (t) async {
          attempts++;
          return false;
        },
      );
      expect(await s.handle('osu-storage://share/abc'), isFalse);
      expect(attempts, 5);
    });

    test('start 監聽 stream，收到的連結會被處理（含百分比編碼）', () async {
      final c = StreamController<Uri>();
      final opened = <String>[];
      final got = Completer<void>();
      final s = AppLinkService(
        links: c.stream,
        ready: () async {},
        open: (t) async {
          opened.add(t);
          got.complete();
          return true;
        },
      );
      s.start();
      s.start(); // 重複呼叫無效
      c.add(Uri.parse('osu-storage://share/a%2Db'));
      await got.future;
      expect(opened, ['a-b']);
      await s.stop();
      await c.close();
    });
  });
}
