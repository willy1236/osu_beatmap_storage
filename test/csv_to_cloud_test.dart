import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/models/csv_row.dart';
import 'package:osu_beatmap_storage/utils/beatmap_csv.dart';
import 'package:osu_beatmap_storage/utils/csv_to_cloud.dart';

CsvRow row(List<String> fields) =>
    CsvRow({for (var i = 0; i < fields.length; i++) kCsvHeader[i]: fields[i]});

void main() {
  final now = DateTime(2026, 10, 23, 12, 30);

  test('完整的一列各欄位反解析', () {
    final r = csvRowsToCloudEntries([
      row([
        '123',
        'T',
        'TU',
        'A',
        'AU',
        'C',
        'Ranked',
        '5',
        'osu/taiko',
        '1.50',
        '5.25',
        '120-180',
        '2024-01-05',
        '2023-12-31',
      ]),
    ], now: now);
    expect(r.skipped, 0);
    final e = r.entries.single;
    expect(e.onlineId, 123);
    expect(
      [e.title, e.titleUnicode, e.artist, e.artistUnicode, e.creator],
      ['T', 'TU', 'A', 'AU', 'C'],
    );
    expect(e.status, 1);
    expect(e.difficultyCount, 5);
    expect(e.modes, ['osu', 'taiko']);
    expect([e.minStar, e.maxStar], [1.5, 5.25]);
    expect([e.minBpm, e.maxBpm], [120, 180]);
    expect(e.dateAdded, DateTime(2024, 1, 5));
    expect(e.dateSubmitted, DateTime(2023, 12, 31));
  });

  test('OnlineID 空白、0、負數、格式錯誤的列略過並計數', () {
    final r = csvRowsToCloudEntries([
      row(['', 'a']),
      row(['0', 'a']),
      row(['-5', 'a']),
      row(['abc', 'a']),
      row([' 7 ', 'ok']),
    ], now: now);
    expect(r.skipped, 4);
    expect(r.entries.map((e) => e.onlineId), [7]);
  });

  test('Status：標籤、數字、未知', () {
    int s(String v) => csvRowsToCloudEntries([
      row(['1', '', '', '', '', '', v]),
    ], now: now).entries.single.status;
    expect(s('Unknown'), -3);
    expect(s('墓地'), -2);
    expect(s('WIP'), -1);
    expect(s('Pending'), 0);
    expect(s('Ranked'), 1);
    expect(s('Approved'), 2);
    expect(s('Qualified'), 3);
    expect(s('Loved'), 4);
    expect(s('3'), 3);
    expect(s('9'), -3);
    expect(s('???'), -3);
    expect(s(''), -3);
  });

  test('模式：略過 ? 與空字串、去重', () {
    List<String> m(String v) => csvRowsToCloudEntries([
      row(['1', '', '', '', '', '', '', '', v]),
    ], now: now).entries.single.modes;
    expect(m('osu'), ['osu']);
    expect(m('osu/?/mania'), ['osu', 'mania']);
    expect(m('?'), isEmpty);
    expect(m(''), isEmpty);
    expect(m('osu/osu'), ['osu']);
  });

  test('BPM：單值、範圍、空白、壞值', () {
    (double?, double?) b(String v) {
      final e = csvRowsToCloudEntries([
        row(['1', '', '', '', '', '', '', '', '', '', '', v]),
      ], now: now).entries.single;
      return (e.minBpm, e.maxBpm);
    }

    expect(b('140'), (140.0, 140.0));
    expect(b('90-200'), (90.0, 200.0));
    expect(b(''), (null, null));
    expect(b('abc'), (null, null));
    expect(b('1-2-3'), (null, null));
  });

  test('舊版 CSV 缺欄位：只有 OnlineID 與標題也能轉，缺的留空', () {
    final r = csvRowsToCloudEntries([
      CsvRow({'OnlineID': '55', 'Title': 'old'}),
    ], now: now);
    final e = r.entries.single;
    expect(e.title, 'old');
    expect(e.creator, '');
    expect(e.status, -3);
    expect(e.difficultyCount, 0);
    expect(e.modes, isEmpty);
    expect(e.minStar, isNull);
    expect(e.minBpm, isNull);
    expect(e.dateSubmitted, isNull);
    expect(e.dateAdded, now);
  });

  test('日期：缺值、壞值用 now；不存在的日期視為壞值；提交日期壞值為 null', () {
    CsvCloudConversion c(String added, String submitted) =>
        csvRowsToCloudEntries([
          row([
            '1',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            added,
            submitted,
          ]),
        ], now: now);
    expect(c('', '').entries.single.dateAdded, now);
    expect(c('yesterday', 'x').entries.single.dateAdded, now);
    expect(c('2024-02-30', '').entries.single.dateAdded, now);
    expect(c('2024-02-29', '2024-13-01').entries.single.dateSubmitted, isNull);
    expect(c('2024-02-29', '').entries.single.dateAdded, DateTime(2024, 2, 29));
  });

  test('toJson 的日期帶時區（UTC，結尾 Z），轉回當地是當天 00:00', () {
    final e = csvRowsToCloudEntries([
      row(['1', '', '', '', '', '', '', '', '', '', '', '', '2024-01-05']),
    ], now: now).entries.single;
    final s = e.toJson()['date_added'] as String;
    expect(s, endsWith('Z'));
    expect(DateTime.parse(s).toLocal(), DateTime(2024, 1, 5));
  });

  test('重複 OnlineID 都保留（由後端合併）', () {
    final r = csvRowsToCloudEntries([
      row(['9', 'a']),
      row(['9', 'b']),
    ], now: now);
    expect(r.entries.length, 2);
    expect(r.skipped, 0);
  });
}
