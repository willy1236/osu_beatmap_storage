import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/tray_service.dart';

class _FakePlatform implements TrayPlatform {
  final calls = <String>[];
  late VoidCallback onClose, onClick, onQuit;

  @override
  Future<void> init({
    required VoidCallback onCloseRequested,
    required VoidCallback onTrayIconClick,
    required VoidCallback onQuitSelected,
  }) async {
    onClose = onCloseRequested;
    onClick = onTrayIconClick;
    onQuit = onQuitSelected;
    calls.add('init');
  }

  @override
  Future<void> hideWindow() async => calls.add('hide');
  @override
  Future<void> showWindow() async => calls.add('show');
  @override
  Future<void> destroyWindow() async => calls.add('destroy');
  @override
  Future<void> showTrayIcon() async => calls.add('trayOn');
  @override
  Future<void> removeTrayIcon() async => calls.add('trayOff');
}

void main() {
  late _FakePlatform platform;
  late CloseAction stored;
  late CloseChoice? answer;
  late int asked;
  late TrayService service;

  setUp(() {
    platform = _FakePlatform();
    stored = CloseAction.ask;
    answer = null;
    asked = 0;
    service = TrayService(
      platform: platform,
      readCloseAction: () async => stored,
      saveCloseAction: (a) async => stored = a,
      askCloseAction: () async {
        asked++;
        return answer;
      },
    );
  });

  test('ask：選縮到系統匣但不記住 -> 隱藏，設定維持 ask', () async {
    answer = (action: CloseAction.tray, remember: false);
    await service.handleCloseRequested();
    expect(platform.calls, ['trayOn', 'hide']);
    expect(service.inTray, isTrue);
    expect(stored, CloseAction.ask);
  });

  test('ask：選縮到系統匣並記住 -> 存設定，下次不再詢問', () async {
    answer = (action: CloseAction.tray, remember: true);
    await service.handleCloseRequested();
    expect(stored, CloseAction.tray);
    await service.handleCloseRequested();
    expect(asked, 1);
    expect(platform.calls, ['trayOn', 'hide', 'trayOn', 'hide']);
  });

  test('ask：選結束並記住 -> 結束，之後直接結束', () async {
    answer = (action: CloseAction.exit, remember: true);
    await service.handleCloseRequested();
    expect(stored, CloseAction.exit);
    expect(platform.calls, ['trayOff', 'destroy']);
    await service.handleCloseRequested();
    expect(asked, 1);
  });

  test('ask：按叉或取消（null）-> 不關閉、不存設定', () async {
    answer = null;
    await service.handleCloseRequested();
    expect(platform.calls, isEmpty);
    expect(stored, CloseAction.ask);
    expect(service.inTray, isFalse);
  });

  test('設定為 tray／exit 時不詢問', () async {
    stored = CloseAction.tray;
    await service.handleCloseRequested();
    expect(asked, 0);
    expect(platform.calls, ['trayOn', 'hide']);
    platform.calls.clear();
    stored = CloseAction.exit;
    await service.handleCloseRequested();
    expect(asked, 0);
    expect(platform.calls, ['trayOff', 'destroy']);
  });

  test('詢問中再次要求關閉會被忽略', () async {
    service = TrayService(
      platform: platform,
      readCloseAction: () async => CloseAction.ask,
      saveCloseAction: (_) async {},
      askCloseAction: () async {
        asked++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return null;
      },
    );
    final first = service.handleCloseRequested();
    await service.handleCloseRequested();
    await first;
    expect(asked, 1);
  });

  test('還原：顯示視窗、移除圖示；匣選單結束：移除圖示後結束', () async {
    await service.init();
    await service.hideToTray();
    platform.calls.clear();
    platform.onClick();
    await Future<void>.delayed(Duration.zero);
    expect(platform.calls, ['show', 'trayOff']);
    expect(service.inTray, isFalse);
    platform.calls.clear();
    platform.onQuit();
    await Future<void>.delayed(Duration.zero);
    expect(platform.calls, ['trayOff', 'destroy']);
  });

  test('CloseAction.parse 不認得的值回 ask', () {
    expect(CloseAction.parse(null), CloseAction.ask);
    expect(CloseAction.parse('tray'), CloseAction.tray);
    expect(CloseAction.parse('x'), CloseAction.ask);
  });
}
