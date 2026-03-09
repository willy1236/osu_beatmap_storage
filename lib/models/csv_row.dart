class CsvRow {
  final Map<String, String> data;
  const CsvRow(this.data);
  String operator [](String key) => data[key] ?? '';
}
