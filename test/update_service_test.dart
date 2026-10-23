import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
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

  test('先取得舊程式 Handle 才寫 started 標記', () {
    final src = UpdateService.applyScriptSource;
    final handle = src.indexOf('[void]\$proc.Handle');
    final flag = src.indexOf(r'Set-Content -LiteralPath $Started');
    expect(handle, greaterThan(0));
    expect(flag, greaterThan(handle));
  });

  test('更新腳本必須是純 ASCII', () {
    final bad = UpdateService.applyScriptSource.codeUnits.where((c) => c > 127);
    expect(bad, isEmpty);
  });

  group('describeError', () {
    test('拿掉 Exception 前綴', () {
      expect(UpdateService.describeError(Exception('boom')), '更新失敗：boom');
      expect(
        UpdateService.describeError(const UpdateException('找不到')),
        '更新失敗：找不到',
      );
    });

    test('Dio 例外不顯示類別前綴', () {
      final e = DioException(
        requestOptions: RequestOptions(path: 'x'),
        message: 'timeout',
      );
      expect(UpdateService.describeError(e), '更新失敗：timeout');
    });

    test('標記逾時的訊息提示手動下載', () {
      expect(
        UpdateService.describeError(
          const UpdateException(UpdateService.launchFailedMessage),
        ),
        '更新失敗：更新程式沒有啟動，請改為手動下載 zip 更新',
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
          return await Process.start('powershell', [
            '-NoProfile',
            '-Command',
            'Start-Sleep 3',
          ]);
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

    test('腳本在寫標記前就結束：立即回傳 false，不等逾時', () async {
      final sw = Stopwatch()..start();
      final ok = await UpdateService.launchApplyScript(
        start: () => Process.start('cmd', ['/c', 'exit']),
        started: File('${dir.path}/started.flag'),
        timeout: const Duration(seconds: 20),
        interval: const Duration(milliseconds: 10),
      );
      expect(ok, isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    }, skip: !Platform.isWindows);

    test('逾時會寫 cancel 標記', () async {
      final flag = File('${dir.path}/started.flag');
      final ok = await UpdateService.launchApplyScript(
        start: () => Process.start('powershell', [
          '-NoProfile',
          '-Command',
          'Start-Sleep 5',
        ]),
        started: flag,
        timeout: const Duration(milliseconds: 200),
        interval: const Duration(milliseconds: 10),
      );
      expect(ok, isFalse);
      expect(File('${flag.path}.cancel').existsSync(), isTrue);
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

  group('真實腳本', () {
    // 每個 case 在獨立資料夾執行；用 cmd 當「新版執行檔」，啟動後寫 ran.txt 當作重啟訊號
    Future<({Directory source, Directory target, File started})> setup(
      String name, {
      bool cmdExe = true,
    }) async {
      final root = Directory.systemTemp.createTempSync('upd real');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } on FileSystemException {
          // 剛啟動的程序可能還鎖著資料夾，留給系統清理
        }
      });
      final base = '${root.path}/$name';
      final source = Directory('$base/src')..createSync(recursive: true);
      final target = Directory('$base/app')..createSync(recursive: true);
      File('${source.path}/new.dll').writeAsStringSync('new');
      File('${target.path}/old.dll').writeAsStringSync('old');
      if (cmdExe) {
        // 路徑不含特殊字元時才能用 cmd 腳本當執行檔；寫入 ran.txt 作為重啟訊號
        File(
          '${source.path}/run.cmd',
        ).writeAsStringSync('@echo ran> "%~dp0ran.txt"');
        File(
          '${target.path}/run.cmd',
        ).writeAsStringSync('@echo ran> "%~dp0ran.txt"');
      } else {
        // 用會立刻結束的真實 exe 當作「新版執行檔」
        File(
          '${Platform.environment['SystemRoot']}/System32/hostname.exe',
        ).copySync('${source.path}/run.exe');
      }
      // 與正式路徑一致：UTF-8 BOM + 腳本內容
      File('${root.path}/apply.ps1').writeAsBytesSync([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(UpdateService.applyScriptSource),
      ]);
      return (
        source: source,
        target: target,
        started: File('${root.path}/started.flag'),
      );
    }

    Future<bool> run(
      ({Directory source, Directory target, File started}) c, {
      required int appPid,
      String exe = 'run.cmd',
      int waitSeconds = 60,
    }) {
      final script = '${c.started.parent.path}/apply.ps1';
      return UpdateService.launchApplyScript(
        start: () => Process.start(
          'powershell',
          UpdateService.applyScriptArgs(
            script: script,
            appPid: appPid,
            source: c.source.path,
            target: c.target.path,
            exe: exe,
            started: c.started.path,
            waitSeconds: waitSeconds,
          ),
        ),
        started: c.started,
        timeout: const Duration(seconds: 30),
      );
    }

    Future<void> until(bool Function() cond) async {
      for (var i = 0; i < 150 && !cond(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    Future<int> deadPid() async =>
        (await Process.run('cmd', ['/c', 'exit'])).pid;

    test('路徑含空格與 % 也能啟動並完成替換', () async {
      final c = await setup('a b %TEMP% & ^ (x)', cmdExe: false);
      expect(await run(c, appPid: await deadPid(), exe: 'run.exe'), isTrue);
      // 標記出現時腳本還在跑，等替換完成（Source 被清掉是最後一步）
      await until(() => !c.source.existsSync());
      expect(File('${c.target.path}/new.dll').existsSync(), isTrue);
      expect(File('${c.target.path}/old.dll').existsSync(), isFalse);
      expect(File('${c.target.path}/run.exe').existsSync(), isTrue);
    });

    test('舊程式逾時仍在執行：不換檔、不重啟', () async {
      final c = await setup('alive');
      final sleeper = await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        'Start-Sleep 60',
      ]);
      addTearDown(sleeper.kill);
      expect(await run(c, appPid: sleeper.pid, waitSeconds: 1), isTrue);
      final log = File('${c.target.path}/update_error.log');
      await until(log.existsSync);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(log.existsSync(), isTrue);
      expect(File('${c.target.path}/old.dll').existsSync(), isTrue);
      expect(File('${c.target.path}/new.dll').existsSync(), isFalse);
      expect(File('${c.target.path}/ran.txt').existsSync(), isFalse);
      expect(c.source.existsSync(), isFalse); // 放棄更新也會清掉暫存
    });

    Future<Process> lockFile(String path) async {
      final holder = await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        "\$f=[IO.File]::Open('$path','Open','Read','None'); 'locked'; Start-Sleep 60",
      ]);
      addTearDown(holder.kill);
      await holder.stdout
          .transform(utf8.decoder)
          .firstWhere((t) => t.contains('locked'));
      return holder;
    }

    Future<void> finish(
      ({Directory source, Directory target, File started}) c,
    ) async {
      expect(await run(c, appPid: await deadPid()), isTrue);
      final ran = File('${c.target.path}/ran.txt');
      await until(ran.existsSync);
      expect(ran.existsSync(), isTrue, reason: '一定要重啟');
    }

    test('成功路徑：同名使用者資料夾合併，使用者檔保留', () async {
      final c = await setup('userdir');
      Directory('${c.source.path}/bin').createSync();
      File('${c.source.path}/bin/tool.txt').writeAsStringSync('v2');
      Directory('${c.target.path}/bin/danser').createSync(recursive: true);
      File('${c.target.path}/bin/danser/danser.txt').writeAsStringSync('user');
      await finish(c);
      final t = c.target.path;
      expect(File('$t/bin/danser/danser.txt').readAsStringSync(), 'user');
      expect(File('$t/bin/tool.txt').readAsStringSync(), 'v2');
      expect(File('$t/new.dll').existsSync(), isTrue);
      expect(File('$t/old.dll').existsSync(), isFalse);
    });

    test('殘留 .update_backup：改名保留、不還原，更新正常', () async {
      final c = await setup('stale');
      final t = c.target.path;
      File('$t/native_assets.json').writeAsStringSync('v2');
      Directory('$t/.update_backup').createSync();
      File('$t/.update_backup/native_assets.json').writeAsStringSync('v1');
      File('$t/.update_backup/stale.dll').writeAsStringSync('v1');
      await finish(c);
      expect(File('$t/native_assets.json').readAsStringSync(), 'v2');
      expect(File('$t/stale.dll').existsSync(), isFalse);
      expect(File('$t/new.dll').existsSync(), isTrue);
      final kept = Directory(t)
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('.update_backup_'))
          .toList();
      expect(kept, hasLength(1));
      expect(File('${kept.single.path}/stale.dll').readAsStringSync(), 'v1');
      expect(
        File('$t/update_error.log').readAsStringSync(),
        contains('leftover'),
      );
    });

    test('殘留備份被鎖住無法改名：改用新備份目錄，仍更新並重啟', () async {
      final c = await setup('stalelock');
      final backup = Directory('${c.target.path}/.update_backup')..createSync();
      final lockPath = '${backup.path}/x.bin';
      File(lockPath).writeAsStringSync('x');
      await lockFile(lockPath);
      await finish(c);
      expect(File('${c.target.path}/new.dll').existsSync(), isTrue);
      expect(File('${c.target.path}/old.dll').existsSync(), isFalse);
      expect(File(lockPath).existsSync(), isTrue);
    });

    test('搬移中途失敗：只回滾程式檔，其他項目不動，仍重啟', () async {
      final c = await setup('rollback');
      final t = c.target.path;
      File('$t/a.dll').writeAsStringSync('A');
      File('$t/native_assets.json').writeAsStringSync('old-manifest');
      Directory('$t/bin').createSync();
      File('$t/bin/u.txt').writeAsStringSync('user');
      // z.dll 被鎖住，搬到備份時失敗；a.dll、old.dll 已先搬走，需被回滾
      await lockFile((File('$t/z.dll')..writeAsStringSync('Z')).path);
      await finish(c);
      expect(File('$t/a.dll').readAsStringSync(), 'A');
      expect(File('$t/old.dll').readAsStringSync(), 'old');
      expect(File('$t/native_assets.json').readAsStringSync(), 'old-manifest');
      expect(File('$t/bin/u.txt').readAsStringSync(), 'user');
      expect(File('$t/new.dll').existsSync(), isFalse);
      expect(Directory('$t/.update_backup').existsSync(), isFalse);
      expect(File('$t/update_error.log').existsSync(), isTrue);
    });

    test('複製程式檔失敗：清掉新檔、還原舊程式檔，其他項目與更新前一致', () async {
      final c = await setup('copyfail');
      final t = c.target.path;
      File(
        '${c.source.path}/native_assets.json',
      ).writeAsStringSync('new-manifest');
      File('$t/native_assets.json').writeAsStringSync('old-manifest');
      Directory('$t/bin').createSync();
      File('$t/bin/u.txt').writeAsStringSync('user');
      // 排在最後的來源 dll 被獨佔鎖住，複製到它時失敗
      final lockPath = '${c.source.path}/zzlock.dll';
      File(lockPath).writeAsStringSync('x');
      await lockFile(lockPath);
      await finish(c);
      expect(File('$t/old.dll').readAsStringSync(), 'old');
      expect(File('$t/native_assets.json').readAsStringSync(), 'old-manifest');
      expect(File('$t/bin/u.txt').readAsStringSync(), 'user');
      expect(File('$t/new.dll').existsSync(), isFalse);
      expect(File('$t/run.cmd').existsSync(), isTrue);
      expect(Directory('$t/.update_backup').existsSync(), isFalse);
      expect(Directory('$t/.update_staging').existsSync(), isFalse);
      expect(File('$t/update_error.log').existsSync(), isTrue);
    });

    test('rename 階段失敗：新檔退回、舊檔還原，Target 與更新前一致', () async {
      final c = await setup('placefail');
      final t = c.target.path;
      File('${c.source.path}/a_new.dll').writeAsStringSync('a-new');
      // Target 有名為 new.dll 的資料夾，新檔 rename 進來時會失敗；a_new.dll 已先放入，需退回
      Directory('$t/new.dll').createSync();
      File('$t/new.dll/keep.txt').writeAsStringSync('keep');
      await finish(c);
      expect(File('$t/old.dll').readAsStringSync(), 'old');
      expect(File('$t/a_new.dll').existsSync(), isFalse);
      expect(File('$t/new.dll/keep.txt').readAsStringSync(), 'keep');
      expect(Directory('$t/.update_backup').existsSync(), isFalse);
      expect(Directory('$t/.update_staging').existsSync(), isFalse);
      expect(File('$t/update_error.log').existsSync(), isTrue);
    });

    test('只有精確 .dll 副檔名才算程式檔（.dllx、.dll_bak 不備份不刪除）', () async {
      final c = await setup('dllext');
      final t = c.target.path;
      File('$t/x.dllx').writeAsStringSync('x');
      File('$t/y.dll_bak').writeAsStringSync('y');
      await finish(c);
      expect(File('$t/x.dllx').readAsStringSync(), 'x');
      expect(File('$t/y.dll_bak').readAsStringSync(), 'y');
      expect(File('$t/old.dll').existsSync(), isFalse);
      expect(File('$t/new.dll').existsSync(), isTrue);
    });

    test('收到 cancel 標記：不換檔、不重啟', () async {
      final c = await setup('cancel');
      File('${c.started.path}.cancel').writeAsStringSync('cancel');
      expect(await run(c, appPid: await deadPid()), isTrue);
      final t = c.target.path;
      final log = File('$t/update_error.log');
      await until(log.existsSync);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(log.readAsStringSync(), contains('cancel'));
      expect(File('$t/old.dll').existsSync(), isTrue);
      expect(File('$t/new.dll').existsSync(), isFalse);
      expect(File('$t/ran.txt').existsSync(), isFalse);
    });

    test('合併複製其他項目失敗：只記 log，新程式檔保留並重啟', () async {
      final c = await setup('mergefail');
      final lockPath = '${c.source.path}/zzlock.bin';
      File(lockPath).writeAsStringSync('x');
      await lockFile(lockPath);
      await finish(c);
      final t = c.target.path;
      expect(File('$t/new.dll').existsSync(), isTrue);
      expect(File('$t/old.dll').existsSync(), isFalse);
      expect(File('$t/update_error.log').readAsStringSync(), contains('merge'));
    });

    test('Target 路徑含 [ ] 也能備份、更新與重啟', () async {
      final c = await setup('app [x]');
      expect(await run(c, appPid: await deadPid()), isTrue);
      final ran = File('${c.target.path}/ran.txt');
      await until(ran.existsSync);
      expect(ran.existsSync(), isTrue);
      expect(File('${c.target.path}/new.dll').existsSync(), isTrue);
      expect(File('${c.target.path}/old.dll').existsSync(), isFalse);
      expect(File('${c.target.path}/update_error.log').existsSync(), isFalse);
    });
  }, skip: !Platform.isWindows);
}
