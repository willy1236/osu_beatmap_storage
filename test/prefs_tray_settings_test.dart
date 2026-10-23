import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/prefs_service.dart';

void main() {
  late Directory original;
  late Directory tmp;

  setUp(() {
    original = Directory.current;
    tmp = Directory.systemTemp.createTempSync('prefs_tray_');
    Directory.current = tmp;
  });

  tearDown(() {
    Directory.current = original;
    tmp.deleteSync(recursive: true);
  });

  test('closeAction 預設 ask，寫入後讀得回來', () async {
    expect(await PrefsService.getCloseAction(), 'ask');
    await PrefsService.setCloseAction('tray');
    expect(await PrefsService.getCloseAction(), 'tray');
    await PrefsService.setCloseAction('exit');
    expect(await PrefsService.getCloseAction(), 'exit');
  });

  test('closeAction 讀到不認得的值當作 ask', () async {
    File('config.json').writeAsStringSync('{"close_action": "boom"}');
    expect(await PrefsService.getCloseAction(), 'ask');
  });

  test('launchAtStartup 預設 false，寫入後讀得回來', () async {
    expect(await PrefsService.getLaunchAtStartup(), isFalse);
    await PrefsService.setLaunchAtStartup(true);
    expect(await PrefsService.getLaunchAtStartup(), isTrue);
  });

  test('兩個設定互不影響，也不動既有欄位', () async {
    await PrefsService.setOsuDir('X:/osu');
    await PrefsService.setCloseAction('tray');
    await PrefsService.setLaunchAtStartup(true);
    expect(await PrefsService.getOsuDir(), 'X:/osu');
    expect(await PrefsService.getCloseAction(), 'tray');
    expect(await PrefsService.getLaunchAtStartup(), isTrue);
  });
}
