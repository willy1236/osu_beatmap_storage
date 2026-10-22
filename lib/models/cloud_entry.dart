import 'osu_realm_models.dart';

/// 雲端清單的一筆圖譜，對應後端契約的 BeatmapEntry
/// （domalyze-api 的 docs/tickets/osu-cloud-beatmap-sync.md〈API 契約〉）。
///
/// 欄位是結構化值（status 代碼、modes 陣列、星數與 BPM 的最小最大值），
/// 與 CSV 匯出的顯示字串不同；CSV 另由 `csvFieldsOf` 計算。
class CloudEntry {
  const CloudEntry({
    required this.onlineId,
    this.title = '',
    this.titleUnicode = '',
    this.artist = '',
    this.artistUnicode = '',
    this.creator = '',
    this.status = -3,
    this.difficultyCount = 0,
    this.modes = const [],
    this.minStar,
    this.maxStar,
    this.minBpm,
    this.maxBpm,
    required this.dateAdded,
    this.dateSubmitted,
  });

  final int onlineId;
  final String title;
  final String titleUnicode;
  final String artist;
  final String artistUnicode;
  final String creator;
  final int status;
  final int difficultyCount;
  final List<String> modes;
  final double? minStar;
  final double? maxStar;
  final double? minBpm;
  final double? maxBpm;
  final DateTime dateAdded;
  final DateTime? dateSubmitted;

  /// 後端的 `date_added`／`date_submitted` 要求含時區，所以一律轉成 UTC 再輸出
  /// （本地時間的 ISO 字串不帶偏移，會被後端以 422 拒收）。
  Map<String, dynamic> toJson() => {
    'online_id': onlineId,
    'title': title,
    'title_unicode': titleUnicode,
    'artist': artist,
    'artist_unicode': artistUnicode,
    'creator': creator,
    'status': status,
    'difficulty_count': difficultyCount,
    'modes': modes,
    'min_star': minStar,
    'max_star': maxStar,
    'min_bpm': minBpm,
    'max_bpm': maxBpm,
    'date_added': dateAdded.toUtc().toIso8601String(),
    'date_submitted': dateSubmitted?.toUtc().toIso8601String(),
  };

  factory CloudEntry.fromJson(Map<String, dynamic> json) => CloudEntry(
    onlineId: json['online_id'] as int,
    title: json['title'] as String? ?? '',
    titleUnicode: json['title_unicode'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    artistUnicode: json['artist_unicode'] as String? ?? '',
    creator: json['creator'] as String? ?? '',
    status: json['status'] as int? ?? -3,
    difficultyCount: json['difficulty_count'] as int? ?? 0,
    modes: [...?(json['modes'] as List?)?.cast<String>()],
    minStar: (json['min_star'] as num?)?.toDouble(),
    maxStar: (json['max_star'] as num?)?.toDouble(),
    minBpm: (json['min_bpm'] as num?)?.toDouble(),
    maxBpm: (json['max_bpm'] as num?)?.toDouble(),
    dateAdded: DateTime.parse(json['date_added'] as String),
    dateSubmitted: json['date_submitted'] == null
        ? null
        : DateTime.parse(json['date_submitted'] as String),
  );
}

/// 本機圖譜集轉成雲端的一筆。星數與 BPM 只計大於 0 的值，送原始 double；
/// 沒有 ruleset 的難度不放進 modes。
CloudEntry toCloudEntry(BeatmapSetInfo s) {
  final meta = s.beatmaps.isNotEmpty ? s.beatmaps.first.metadata : null;
  final stars = s.beatmaps.map((b) => b.starRating).where((r) => r > 0);
  final bpms = s.beatmaps.map((b) => b.bpm).where((b) => b > 0);
  final modes = <String>[];
  for (final b in s.beatmaps) {
    final name = b.ruleset?.shortName;
    if (name != null && !modes.contains(name)) modes.add(name);
  }
  return CloudEntry(
    onlineId: s.onlineID,
    title: meta?.title ?? '',
    titleUnicode: meta?.titleUnicode ?? '',
    artist: meta?.artist ?? '',
    artistUnicode: meta?.artistUnicode ?? '',
    creator: meta?.author?.username ?? '',
    status: s.status,
    difficultyCount: s.beatmaps.length,
    modes: modes,
    minStar: stars.isEmpty ? null : stars.reduce((a, b) => a < b ? a : b),
    maxStar: stars.isEmpty ? null : stars.reduce((a, b) => a > b ? a : b),
    minBpm: bpms.isEmpty ? null : bpms.reduce((a, b) => a < b ? a : b),
    maxBpm: bpms.isEmpty ? null : bpms.reduce((a, b) => a > b ? a : b),
    dateAdded: s.dateAdded,
    dateSubmitted: s.dateSubmitted,
  );
}
