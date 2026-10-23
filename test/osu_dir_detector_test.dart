import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/osu_dir_detector.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory appData;

  setUp(() async {
    appData = await Directory.systemTemp.createTemp('osu_dir_detector_');
  });

  tearDown(() => appData.delete(recursive: true));

  Future<void> touchRealm(String dir) async {
    await Directory(dir).create(recursive: true);
    await File(p.join(dir, 'client.realm')).writeAsString('');
  }

  test('沒有任何資料時回 null', () async {
    expect(await OsuDirDetector.detect(appData: appData.path), isNull);
  });

  test('預設位置有 client.realm', () async {
    final dir = p.join(appData.path, 'osu');
    await touchRealm(dir);
    expect(await OsuDirDetector.detect(appData: appData.path), dir);
  });

  test('storage.ini 指向的位置優先', () async {
    final defaultDir = p.join(appData.path, 'osu');
    final custom = p.join(appData.path, 'custom lazer');
    await touchRealm(defaultDir);
    await touchRealm(custom);
    await File(
      p.join(defaultDir, 'storage.ini'),
    ).writeAsString('FullPath = $custom\n');
    expect(await OsuDirDetector.detect(appData: appData.path), custom);
  });

  test('storage.ini 指向的位置沒有 client.realm 時退回預設位置', () async {
    final defaultDir = p.join(appData.path, 'osu');
    await touchRealm(defaultDir);
    await File(
      p.join(defaultDir, 'storage.ini'),
    ).writeAsString('FullPath = ${p.join(appData.path, 'gone')}\n');
    expect(await OsuDirDetector.detect(appData: appData.path), defaultDir);
  });
}
