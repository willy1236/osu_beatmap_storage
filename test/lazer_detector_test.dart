import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/lazer_detector.dart';
import 'package:path/path.dart' as p;

void main() {
  const local = r'C:\Users\u\AppData\Local';

  group('isLazerExe', () {
    bool f(String path, {bool dll = false}) =>
        isLazerExe(path, localAppData: local, fileExists: (_) => dll);

    test('預設安裝位置：根目錄啟動器與 current 都算', () {
      expect(f(p.join(local, 'osulazer', 'osu!.exe')), isTrue);
      expect(f(p.join(local, 'osulazer', 'current', 'osu!.exe')), isTrue);
    });

    test('stable 不算（路徑不同、資料夾沒有 osu.Game.dll）', () {
      expect(f(p.join(local, 'osu!', 'osu!.exe')), isFalse);
      expect(f(r'D:\Games\osu!\osu!.exe'), isFalse);
    });

    test('自訂安裝位置：同資料夾有 osu.Game.dll 才算', () {
      expect(f(r'D:\lazer\osu!.exe', dll: true), isTrue);
      expect(f(r'D:\lazer\osu!.exe'), isFalse);
    });

    test('檔名不是 osu!.exe 一律不算；osulazer 開頭的其他資料夾不算', () {
      expect(f(p.join(local, 'osulazer', 'Update.exe'), dll: true), isFalse);
      expect(f(p.join(local, 'osulazer-old', 'osu!.exe')), isFalse);
    });
  });

  group('WindowsLazerDetector（真實程序）', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('t10_lazer'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Process> spawn() {
      final exe = File(p.join(dir.path, 'osu!.exe'));
      File(
        p.join(Platform.environment['SystemRoot']!, 'System32', 'ping.exe'),
      ).copySync(exe.path);
      return Process.start(exe.path, ['-n', '30', '127.0.0.1']);
    }

    test(
      '自訂位置：有 osu.Game.dll 偵測到，沒有就不算；程序結束後不再偵測到',
      () async {
        final detector = WindowsLazerDetector(localAppData: dir.path);
        // 先確認環境裡沒有真的 lazer 干擾（本機可能正在玩）
        final before = await detector.isRunning();
        final proc = await spawn();
        addTearDown(proc.kill);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          await WindowsLazerDetector(localAppData: dir.path).isRunning(),
          before,
        );

        File(p.join(dir.path, 'osu.Game.dll')).writeAsStringSync('');
        final sw = Stopwatch()..start();
        expect(
          await WindowsLazerDetector(localAppData: dir.path).isRunning(),
          isTrue,
        );
        sw.stop();
        // ignore: avoid_print
        print('detect ms: ${sw.elapsedMilliseconds}');

        proc.kill();
        await proc.exitCode;
        File(p.join(dir.path, 'osu.Game.dll')).deleteSync();
        expect(
          await WindowsLazerDetector(localAppData: dir.path).isRunning(),
          before,
        );
      },
      skip: Platform.isWindows ? false : '只在 Windows',
    );
  });
}
