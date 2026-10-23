import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/autostart_service.dart';

class _FakeBackend implements AutostartBackend {
  final calls = <String>[];
  bool fail = false;
  @override
  Future<bool> isEnabled() async => true;
  @override
  Future<void> enable() async {
    if (fail) throw StateError('boom');
    calls.add('enable');
  }

  @override
  Future<void> disable() async => calls.add('disable');
}

void main() {
  late _FakeBackend backend;
  late bool saved;
  late int created;
  late AutostartService service;

  setUp(() {
    backend = _FakeBackend();
    saved = false;
    created = 0;
    service = AutostartService(
      backend: () {
        created++;
        return backend;
      },
      readEnabled: () async => saved,
      saveEnabled: (v) async => saved = v,
    );
  });

  test('開啟：寫 Run 項目並存設定；關閉：移除並存設定', () async {
    await service.setEnabled(true);
    expect(backend.calls, ['enable']);
    expect(saved, isTrue);
    await service.setEnabled(false);
    expect(backend.calls, ['enable', 'disable']);
    expect(saved, isFalse);
  });

  test('寫 Run 失敗時設定維持原值並丟出例外', () async {
    backend.fail = true;
    await expectLater(service.setEnabled(true), throwsStateError);
    expect(saved, isFalse);
  });

  test('syncOnStart：設定為關閉時不建立 backend、不碰 registry', () async {
    await service.syncOnStart();
    expect(created, 0);
    expect(backend.calls, isEmpty);
  });

  test('syncOnStart：設定為開啟時重寫 Run 項目；失敗靜默', () async {
    saved = true;
    await service.syncOnStart();
    expect(backend.calls, ['enable']);
    backend.fail = true;
    await service.syncOnStart();
  });
}
