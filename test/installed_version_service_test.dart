import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/installed_version_service.dart';

class _FakeRegistry implements InstallRegistry {
  _FakeRegistry(this.values);
  final Map<String, String> values;
  bool fail = false;
  final writes = <String>[];

  @override
  String? read(String name) {
    if (fail) throw StateError('boom');
    return values[name];
  }

  @override
  void write(String name, String value) {
    writes.add(name);
    values[name] = value;
  }
}

void main() {
  const exeDir = r'C:\Users\me\AppData\Local\Programs\osu_beatmap_storage';

  InstalledVersionService service(
    InstallRegistry? reg, {
    String version = '2.4.0',
  }) => InstalledVersionService(
    open: () => reg,
    version: version,
    exeDir: exeDir,
  );

  test('安裝位置是目前資料夾：寫入新版本', () {
    // Inno Setup 的 InstallLocation 結尾有反斜線，大小寫也可能不同
    final reg = _FakeRegistry({
      'InstallLocation':
          r'c:\users\me\appdata\local\programs\osu_beatmap_storage\',
      'DisplayVersion': '2.3.1',
    });
    service(reg).syncOnStart();
    expect(reg.values['DisplayVersion'], '2.4.0');
  });

  test('版本已相同：不寫入', () {
    final reg = _FakeRegistry({
      'InstallLocation': '$exeDir\\',
      'DisplayVersion': '2.4.0',
    });
    service(reg).syncOnStart();
    expect(reg.writes, isEmpty);
  });

  test('安裝位置是別的資料夾（另一份免安裝版）：不動安裝版紀錄', () {
    final reg = _FakeRegistry({
      'InstallLocation': r'D:\Games\osu_beatmap_storage\',
      'DisplayVersion': '2.3.1',
    });
    service(reg).syncOnStart();
    expect(reg.values['DisplayVersion'], '2.3.1');
  });

  test('沒有解除安裝項目、沒帶版本、讀取失敗：都靜默略過', () {
    expect(() => service(null).syncOnStart(), returnsNormally);

    final reg = _FakeRegistry({
      'InstallLocation': '$exeDir\\',
      'DisplayVersion': '2.3.1',
    });
    service(reg, version: '').syncOnStart();
    expect(reg.writes, isEmpty);

    reg.fail = true;
    expect(() => service(reg).syncOnStart(), returnsNormally);
  });
}
