import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/models/beatmap_set_row.dart';
import 'package:osu_beatmap_storage/models/osu_realm_models.dart';
import 'package:osu_beatmap_storage/widgets/selectable_set_tile.dart';
import 'package:realm/realm.dart';

BeatmapSetRow row(int onlineId) => BeatmapSetRow.from(
  BeatmapSetInfo(Uuid.v4(), onlineId, DateTime.utc(2024), -3, false, false),
);

void main() {
  Future<void> pump(WidgetTester t, int onlineId, List<bool> log) =>
      t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectableSetTile(
              row: row(onlineId),
              selected: false,
              onChanged: log.add,
            ),
          ),
        ),
      );

  testWidgets('有 OnlineID：可勾選', (t) async {
    final log = <bool>[];
    await pump(t, 7, log);
    await t.tap(find.byType(Checkbox));
    expect(log, [true]);
  });

  testWidgets('沒有 OnlineID：勾選框停用', (t) async {
    final log = <bool>[];
    await pump(t, 0, log);
    expect(t.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    await t.tap(find.byType(Checkbox), warnIfMissed: false);
    expect(log, isEmpty);
  });
}
