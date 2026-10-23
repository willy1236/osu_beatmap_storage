import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/auto_upload_service.dart';
import 'package:osu_beatmap_storage/services/cloud_sync_service.dart';
import 'package:osu_beatmap_storage/widgets/auto_upload_setting.dart';
import 'package:osu_beatmap_storage/widgets/settings_dialog.dart';

import 'friend_test_helpers.dart';

void main() {
  AutoUploadService makeAuto(dynamic auth, List<String?> saved) =>
      AutoUploadService(
        auth: auth,
        sync: CloudSyncService(
          api: ApiClient(
            httpClient: MockClient((_) async => http.Response('{}', 200)),
            tokenProvider: () async => 'tok',
            refreshToken: (_) async => null,
            onUnauthorized: () async {},
            baseUrl: 'https://api.test',
          ),
        ),
        readSub: () async => saved.isEmpty ? null : saved.last,
        writeSub: (s) async => saved.add(s),
      );

  Future<void> pumpSetting(WidgetTester t, Widget w) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    await t.pumpAndSettle();
  }

  testWidgets('預設設定清單含自動上傳項目', (t) async {
    expect(defaultSettingsEntries.map((e) => e.title), contains('自動上傳'));
  });

  testWidgets('已登入：可切換自動上傳並寫入設定', (t) async {
    final auth = makeAuth();
    await auth.init();
    final saved = <String?>[];
    final auto = makeAuto(auth, saved);
    await pumpSetting(t, AutoUploadSetting(service: auto, auth: auth));
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value, false);

    await t.tap(find.byType(SwitchListTile));
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value, true);
    expect(saved.last, meId);

    await t.tap(find.byType(SwitchListTile));
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value, false);
    expect(saved.last, isNull);
  });

  testWidgets('未登入：開關停用並提示登入後才能設定', (t) async {
    final auth = makeAuth(loggedIn: false);
    await auth.init();
    final auto = makeAuto(auth, []);
    await pumpSetting(t, AutoUploadSetting(service: auto, auth: auth));
    final sw = t.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.onChanged, isNull);
    expect(find.text('登入後才能設定'), findsOneWidget);
  });
}
