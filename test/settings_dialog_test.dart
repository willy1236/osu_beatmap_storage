import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/services/autostart_service.dart';
import 'package:osu_beatmap_storage/services/tray_service.dart';
import 'package:osu_beatmap_storage/widgets/close_action_dialog.dart';
import 'package:osu_beatmap_storage/widgets/settings_dialog.dart';

class _FakeBackend implements AutostartBackend {
  final calls = <String>[];
  @override
  Future<bool> isEnabled() async => true;
  @override
  Future<void> enable() async => calls.add('enable');
  @override
  Future<void> disable() async => calls.add('disable');
}

Widget _host(void Function(BuildContext) open) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  group('設定對話框', () {
    testWidgets('依序顯示傳入的項目；加一個項目不必改對話框本身', (tester) async {
      await tester.pumpWidget(
        _host(
          (c) => showSettingsDialog(
            c,
            entries: [
              SettingsEntry(title: '甲', builder: (_) => const Text('內容甲')),
              SettingsEntry(title: '乙', builder: (_) => const Text('內容乙')),
            ],
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('設定'), findsOneWidget);
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('內容乙'), findsOneWidget);
    });

    testWidgets('關閉行為可選三種並回呼儲存', (tester) async {
      CloseAction? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloseActionSetting(
              load: () async => CloseAction.ask,
              save: (a) async => saved = a,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('每次詢問'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<CloseAction>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('縮到系統匣').last);
      await tester.pumpAndSettle();
      expect(saved, CloseAction.tray);
      expect(find.text('縮到系統匣'), findsOneWidget);
    });

    testWidgets('開機啟動開關：預設關，打開會呼叫 service', (tester) async {
      final backend = _FakeBackend();
      var stored = false;
      final service = AutostartService(
        backend: () => backend,
        readEnabled: () async => stored,
        saveEnabled: (v) async => stored = v,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AutostartSetting(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(backend.calls, ['enable']);
      expect(stored, isTrue);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });
  });

  group('關閉視窗詢問', () {
    Future<CloseChoice?> run(
      WidgetTester tester,
      Future<void> Function() act,
    ) async {
      CloseChoice? result;
      var done = false;
      await tester.pumpWidget(
        _host((c) {
          showCloseActionDialog(c).then((v) {
            result = v;
            done = true;
          });
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      expect(done, isTrue);
      return result;
    }

    testWidgets('縮到系統匣並記住', (tester) async {
      final r = await run(tester, () async {
        await tester.tap(find.text('記住我的選擇'));
        await tester.tap(find.text('縮到系統匣'));
      });
      expect(r, (action: CloseAction.tray, remember: true));
    });

    testWidgets('結束程式、不記住', (tester) async {
      final r = await run(tester, () => tester.tap(find.text('結束程式')));
      expect(r, (action: CloseAction.exit, remember: false));
    });

    testWidgets('取消回 null（不關閉）', (tester) async {
      final r = await run(tester, () => tester.tap(find.text('取消')));
      expect(r, isNull);
    });
  });
}
