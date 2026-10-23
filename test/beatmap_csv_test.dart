import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/constants.dart';
import 'package:osu_beatmap_storage/models/osu_realm_models.dart';
import 'package:osu_beatmap_storage/utils/beatmap_csv.dart';
import 'package:realm/realm.dart';

/// 改版前 `_exportCsv` 迴圈內的演算法逐字複本，作為 oracle。
List<String> legacyFields(BeatmapSetInfo s) {
  final meta = s.beatmaps.isNotEmpty ? s.beatmaps.first.metadata : null;
  final stars = s.beatmaps.map((b) => b.starRating).where((r) => r > 0).toList()
    ..sort();
  final modes = s.beatmaps
      .map((b) => b.ruleset?.shortName ?? '?')
      .toSet()
      .join('/');
  final bpms = s.beatmaps.map((b) => b.bpm).where((b) => b > 0).toSet().toList()
    ..sort();
  final bpmStr = bpms.isEmpty
      ? ''
      : bpms.length == 1
      ? bpms.first.toStringAsFixed(0)
      : '${bpms.first.toStringAsFixed(0)}-${bpms.last.toStringAsFixed(0)}';
  return [
    s.onlineID.toString(),
    meta?.title ?? '',
    meta?.titleUnicode ?? '',
    meta?.artist ?? '',
    meta?.artistUnicode ?? '',
    meta?.author?.username ?? '',
    kStatusLabel[s.status] ?? s.status.toString(),
    s.beatmaps.length.toString(),
    modes,
    stars.isEmpty ? '' : stars.first.toStringAsFixed(2),
    stars.isEmpty ? '' : stars.last.toStringAsFixed(2),
    bpmStr,
    s.dateAdded.toLocal().toIso8601String().split('T').first,
    s.dateSubmitted?.toLocal().toIso8601String().split('T').first ?? '',
  ];
}

RulesetInfo ruleset(String? name) => RulesetInfo(name, 0, 0, true);

BeatmapInfo bm(
  double star,
  double bpm, {
  RulesetInfo? rs,
  BeatmapMetadata? meta,
}) => BeatmapInfo(
  Uuid.v4(),
  0,
  false,
  0,
  0,
  bpm,
  star,
  ruleset: rs,
  metadata: meta,
);

BeatmapMetadata metaOf({String? author}) => BeatmapMetadata(
  0,
  title: 'T "q", x',
  titleUnicode: '標題',
  artist: 'A',
  artistUnicode: '藝術家',
  author: author == null ? null : RealmUser(1, username: author),
);

BeatmapSetInfo set(
  int id,
  List<BeatmapInfo> maps, {
  int status = 1,
  DateTime? added,
  DateTime? submitted,
}) => BeatmapSetInfo(
  Uuid.v4(),
  id,
  added ?? DateTime.utc(2024, 3, 5, 23, 30),
  status,
  false,
  false,
  dateSubmitted: submitted,
  beatmaps: maps,
);

void main() {
  final fixtures = <String, BeatmapSetInfo>{
    '無 beatmaps': set(1, []),
    'metadata 為 null、ruleset 為 null': set(2, [bm(3.456, 180)]),
    '星數全為 0、BPM 為 0': set(3, [bm(0, 0, rs: ruleset('osu'), meta: metaOf())]),
    'BPM 單值': set(4, [
      bm(
        2.0,
        150,
        rs: ruleset('osu'),
        meta: metaOf(author: '製圖者'),
      ),
      bm(5.5, 150, rs: ruleset('osu')),
    ]),
    'BPM 兩個不同值': set(5, [
      bm(2.0, 120, rs: ruleset('osu'), meta: metaOf()),
      bm(5.5, 180.4, rs: ruleset('taiko')),
    ]),
    'BPM 不同但四捨五入後相同': set(6, [
      bm(2.0, 120.2, rs: ruleset('osu'), meta: metaOf()),
      bm(3.0, 120.4, rs: ruleset('osu')),
    ]),
    '混合模式含 null ruleset': set(7, [
      bm(2.0, 100, rs: ruleset('mania'), meta: metaOf()),
      bm(3.0, 100),
      bm(4.0, 100, rs: ruleset('osu')),
    ]),
    'status 不在對照表': set(8, [bm(1, 1, rs: ruleset('osu'))], status: 9),
    'status 為 Loved、有提交日期': set(
      9,
      [bm(1, 1, rs: ruleset('osu'))],
      status: 4,
      submitted: DateTime.utc(2023, 12, 31, 23, 59),
    ),
    '日期跨午夜': set(10, [bm(1, 1)], added: DateTime.utc(2024, 1, 1, 0, 0, 1)),
  };

  for (final e in fixtures.entries) {
    test('csvFieldsOf 與改版前輸出相同：${e.key}', () {
      final fields = csvFieldsOf(e.value);
      expect(fields, legacyFields(e.value));
      expect(fields.length, kCsvHeader.length);
    });
  }

  test('固定輸出：具體值', () {
    final f = csvFieldsOf(fixtures['BPM 兩個不同值']!);
    expect(f.sublist(0, 12), [
      '5',
      'T "q", x',
      '標題',
      'A',
      '藝術家',
      '',
      'Ranked',
      '2',
      'osu/taiko',
      '2.00',
      '5.50',
      '120-180',
    ]);
  });
}
