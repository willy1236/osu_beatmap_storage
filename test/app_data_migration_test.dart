import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/app_data_migration.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory from;
  late Directory to;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('app_data_migration_');
    from = Directory(p.join(root.path, 'com.example', 'osu_beatmap_storage'));
    to = Directory(
      p.join(root.path, 'Domalyze Studio', 'osu! Beatmap Storage'),
    );
  });

  tearDown(() => root.delete(recursive: true));

  void write(Directory dir, String rel, String content) {
    final f = File(p.join(dir.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  String read(Directory dir, String rel) =>
      File(p.join(dir.path, rel)).readAsStringSync();

  test('搬過去後刪掉舊資料夾與空的上層', () async {
    write(from, 'flutter_secure_storage.dat', 'token');
    write(from, r'bin\a.txt', 'a');

    await moveAppData(from: from, to: to);

    expect(read(to, 'flutter_secure_storage.dat'), 'token');
    expect(read(to, r'bin\a.txt'), 'a');
    expect(from.parent.existsSync(), isFalse);
  });

  test('新位置已有的檔案不覆蓋', () async {
    write(from, 'flutter_secure_storage.dat', 'old');
    write(to, 'flutter_secure_storage.dat', 'new');

    await moveAppData(from: from, to: to);

    expect(read(to, 'flutter_secure_storage.dat'), 'new');
  });

  test('上層還有別的程式的資料夾：只刪自己的', () async {
    write(from, 'flutter_secure_storage.dat', 'token');
    Directory(p.join(from.parent.path, 'other_app')).createSync();

    await moveAppData(from: from, to: to);

    expect(from.existsSync(), isFalse);
    expect(
      Directory(p.join(from.parent.path, 'other_app')).existsSync(),
      isTrue,
    );
  });

  test('沒有舊資料夾：不動作', () async {
    await moveAppData(from: from, to: to);
    expect(to.existsSync(), isFalse);
  });
}
