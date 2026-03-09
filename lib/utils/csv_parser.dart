import '../models/csv_row.dart';

/// CSV 解析工具（支援 RFC 4180 雙引號跳脫）
abstract final class CsvParser {
  static List<CsvRow> parse(String content) {
    final text = content.startsWith('\uFEFF') ? content.substring(1) : content;
    final lines = text
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return [];
    final headers = splitLine(lines[0]);
    final rows = <CsvRow>[];
    for (final line in lines.skip(1)) {
      final fields = splitLine(line);
      if (fields.isEmpty) continue;
      final map = <String, String>{};
      for (var i = 0; i < headers.length && i < fields.length; i++) {
        map[headers[i]] = fields[i];
      }
      rows.add(CsvRow(map));
    }
    return rows;
  }

  static List<String> splitLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          fields.add(buf.toString());
          buf.clear();
        } else {
          buf.write(c);
        }
      }
    }
    fields.add(buf.toString());
    return fields;
  }
}
