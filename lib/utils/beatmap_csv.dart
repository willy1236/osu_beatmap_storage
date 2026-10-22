import '../constants.dart';
import '../models/osu_realm_models.dart';

/// CSV 匯出的表頭（14 個欄位）
const kCsvHeader = <String>[
  'OnlineID',
  'Title',
  'TitleUnicode',
  'Artist',
  'ArtistUnicode',
  'Creator',
  'Status',
  '難度數',
  '模式',
  '最低星數',
  '最高星數',
  'BPM',
  '加入日期',
  '提交日期',
];

/// 一個圖譜集在 CSV 匯出時的 14 個欄位值（與 [kCsvHeader] 對應）。
/// 雲端清單用 `toCloudEntry`（cloud_entry.dart）另算，兩邊刻意分開，確保 CSV 輸出不受雲端格式影響。
List<String> csvFieldsOf(BeatmapSetInfo s) {
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
