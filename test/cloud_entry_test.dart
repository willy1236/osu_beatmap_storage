import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/models/cloud_entry.dart';
import 'package:osu_beatmap_storage/models/osu_realm_models.dart';
import 'package:realm/realm.dart';

BeatmapInfo bm(
  double star,
  double bpm, {
  String? mode,
  BeatmapMetadata? meta,
}) => BeatmapInfo(
  Uuid.v4(),
  0,
  false,
  0,
  0,
  bpm,
  star,
  ruleset: mode == null ? null : RulesetInfo(mode, 0, 0, true),
  metadata: meta,
);

void main() {
  test('toCloudEntry：欄位對應、原始 double、略過 null ruleset', () {
    final meta = BeatmapMetadata(
      0,
      title: 'T',
      titleUnicode: 'TU',
      artist: 'A',
      artistUnicode: 'AU',
      author: RealmUser(1, username: 'mapper'),
    );
    final s = BeatmapSetInfo(
      Uuid.v4(),
      42,
      DateTime.utc(2024, 3, 5, 23, 30),
      4,
      false,
      false,
      dateSubmitted: DateTime.utc(2023, 1, 2),
      beatmaps: [
        bm(2.345, 120.2, mode: 'osu', meta: meta),
        bm(5.5, 180.4, mode: 'taiko'),
        bm(0, 0),
        bm(3.0, 120.2, mode: 'osu'),
      ],
    );
    final e = toCloudEntry(s);
    expect(e.onlineId, 42);
    expect(
      [e.title, e.titleUnicode, e.artist, e.artistUnicode, e.creator],
      ['T', 'TU', 'A', 'AU', 'mapper'],
    );
    expect(e.status, 4);
    expect(e.difficultyCount, 4);
    expect(e.modes, ['osu', 'taiko']);
    expect(e.minStar, 2.345);
    expect(e.maxStar, 5.5);
    expect(e.minBpm, 120.2);
    expect(e.maxBpm, 180.4);
    expect(e.dateAdded, DateTime.utc(2024, 3, 5, 23, 30));
    expect(e.dateSubmitted, DateTime.utc(2023, 1, 2));
  });

  test('toCloudEntry：空 beatmaps 與全 0 星數／BPM', () {
    final e = toCloudEntry(
      BeatmapSetInfo(Uuid.v4(), 7, DateTime.utc(2024), -3, false, false),
    );
    expect(e.title, '');
    expect(e.modes, isEmpty);
    expect(e.minStar, isNull);
    expect(e.maxBpm, isNull);
    expect(e.dateSubmitted, isNull);
    expect(e.difficultyCount, 0);
  });

  test('toJson：日期一律帶 Z、null 欄位為 null、可 jsonEncode', () {
    final local = DateTime(2024, 3, 6, 0, 0); // 本地時間
    final j = CloudEntry(onlineId: 1, dateAdded: local, minStar: 5).toJson();
    expect(j['date_added'], endsWith('Z'));
    expect(DateTime.parse(j['date_added'] as String), local.toUtc());
    expect(j['date_submitted'], isNull);
    expect(j['min_star'], 5.0);
    expect(jsonEncode(j), contains('"min_star":5.0'));
    expect(j.keys.length, 15);
  });

  test('toJson／fromJson 往返', () {
    final e = CloudEntry(
      onlineId: 9,
      title: 't',
      creator: 'c',
      status: 1,
      difficultyCount: 3,
      modes: ['osu', 'mania'],
      minStar: 1.5,
      maxStar: 6,
      minBpm: 100,
      maxBpm: 200.5,
      dateAdded: DateTime.utc(2024, 1, 1, 12),
      dateSubmitted: DateTime.utc(2023, 5, 5),
    );
    final back = CloudEntry.fromJson(
      jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>,
    );
    expect(back.toJson(), e.toJson());
    expect(back.maxStar, 6.0);
  });
}
