import '../constants.dart';
import '../models/cloud_entry.dart';
import '../models/csv_row.dart';

/// CSV 列反解析成雲端清單項目的結果。
class CsvCloudConversion {
  const CsvCloudConversion(this.entries, this.skipped);

  final List<CloudEntry> entries;

  /// OnlineID 空白、0 或格式錯誤而略過的列數
  final int skipped;
}

final _statusByLabel = {
  for (final e in kStatusLabel.entries) e.value.toLowerCase(): e.key,
};
final _datePattern = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');

/// 把 CSV 列（欄位名稱同 `kCsvHeader`）轉成 [CloudEntry]。
/// OnlineID 不是正整數的列略過；缺的欄位留空（字串）、null（數值）或 0；
/// 加入日期缺值或格式錯誤時用 [now]（後端合併取較早值，不會蓋掉雲端既有的日期）。
CsvCloudConversion csvRowsToCloudEntries(
  Iterable<CsvRow> rows, {
  DateTime? now,
}) {
  final fallbackDate = now ?? DateTime.now();
  final entries = <CloudEntry>[];
  var skipped = 0;
  for (final r in rows) {
    final id = int.tryParse(r['OnlineID'].trim()) ?? 0;
    if (id <= 0) {
      skipped++;
      continue;
    }
    final (minBpm, maxBpm) = _parseBpm(r['BPM']);
    entries.add(
      CloudEntry(
        onlineId: id,
        title: r['Title'],
        titleUnicode: r['TitleUnicode'],
        artist: r['Artist'],
        artistUnicode: r['ArtistUnicode'],
        creator: r['Creator'],
        status: _parseStatus(r['Status']),
        difficultyCount: int.tryParse(r['難度數'].trim()) ?? 0,
        modes: _parseModes(r['模式']),
        minStar: double.tryParse(r['最低星數'].trim()),
        maxStar: double.tryParse(r['最高星數'].trim()),
        minBpm: minBpm,
        maxBpm: maxBpm,
        dateAdded: _parseDate(r['加入日期']) ?? fallbackDate,
        dateSubmitted: _parseDate(r['提交日期']),
      ),
    );
  }
  return CsvCloudConversion(entries, skipped);
}

/// 標籤文字（Ranked…）反查代碼；查不到再試數字；仍不行或超出 -3～4 就是 -3（Unknown）
int _parseStatus(String s) {
  final t = s.trim();
  final byLabel = _statusByLabel[t.toLowerCase()];
  if (byLabel != null) return byLabel;
  final n = int.tryParse(t);
  return n != null && n >= -3 && n <= 4 ? n : -3;
}

/// `osu/taiko` → [osu, taiko]；略過空字串與 `?`（匯出時沒有 ruleset 的難度）
List<String> _parseModes(String s) {
  final modes = <String>[];
  for (final m in s.split('/')) {
    final t = m.trim();
    if (t.isNotEmpty && t != '?' && !modes.contains(t)) modes.add(t);
  }
  return modes;
}

/// `120` → (120, 120)；`120-180` → (120, 180)；空白或格式錯誤 → (null, null)
(double?, double?) _parseBpm(String s) {
  final t = s.trim();
  if (t.isEmpty) return (null, null);
  final parts = t.split('-');
  if (parts.length == 1) {
    final v = double.tryParse(parts[0]);
    return (v, v);
  }
  if (parts.length == 2) {
    final a = double.tryParse(parts[0]), b = double.tryParse(parts[1]);
    if (a != null && b != null) return a <= b ? (a, b) : (b, a);
  }
  return (null, null);
}

/// `YYYY-MM-DD` → 當地 00:00；其他格式（含空白）為 null
DateTime? _parseDate(String s) {
  final m = _datePattern.firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final dt = DateTime(y, mo, d);
  // DateTime 會自動進位（2 月 30 日變 3 月 2 日），不一致就當壞值
  return dt.year == y && dt.month == mo && dt.day == d ? dt : null;
}
