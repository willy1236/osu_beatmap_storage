import '../constants.dart';
import 'osu_realm_models.dart';

/// 圖譜查看頁一列要顯示的內容，載入時一次從 Realm 讀好；
/// 捲動時 tile 只讀這裡的欄位，不再逐列呼叫 Realm
class BeatmapSetRow {
  final BeatmapSetInfo set;
  final int onlineID;
  final String title;
  final String artist;
  final String statusText;
  final int difficultyCount;
  final String addedStr;
  final String modeLabel;

  /// 由小到大，只含大於 0 的星數
  final List<double> stars;

  /// 搜尋用：標題與藝術家（含 Unicode）轉小寫後以換行串接
  final String searchText;

  BeatmapSetRow._({
    required this.set,
    required this.onlineID,
    required this.title,
    required this.artist,
    required this.statusText,
    required this.difficultyCount,
    required this.addedStr,
    required this.modeLabel,
    required this.stars,
    required this.searchText,
  });

  factory BeatmapSetRow.from(BeatmapSetInfo set) {
    final beatmaps = set.beatmaps.toList();
    final meta = beatmaps.isNotEmpty ? beatmaps.first.metadata : null;
    final titleUnicode = meta?.titleUnicode;
    final titleRaw = meta?.title;
    final artistUnicode = meta?.artistUnicode;
    final artistRaw = meta?.artist;

    final added = set.dateAdded.toLocal();
    final modes = beatmaps.map((b) => b.ruleset?.shortName ?? '?').toSet();

    return BeatmapSetRow._(
      set: set,
      onlineID: set.onlineID,
      title: (titleUnicode?.isNotEmpty == true)
          ? titleUnicode!
          : (titleRaw ?? '（未知標題）'),
      artist: (artistUnicode?.isNotEmpty == true)
          ? artistUnicode!
          : (artistRaw ?? '（未知藝術家）'),
      statusText: kStatusLabel[set.status] ?? '?',
      difficultyCount: beatmaps.length,
      addedStr:
          '${added.year}/${added.month.toString().padLeft(2, '0')}/${added.day.toString().padLeft(2, '0')}',
      modeLabel: modes.length == 1 ? modes.first : '♫',
      stars: beatmaps.map((b) => b.starRating).where((s) => s > 0).toList()
        ..sort(),
      searchText: meta == null
          ? ''
          : [
              titleRaw,
              artistRaw,
              titleUnicode,
              artistUnicode,
            ].map((s) => s?.toLowerCase() ?? '').join('\n'),
    );
  }
}
