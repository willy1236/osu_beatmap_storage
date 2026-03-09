import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:realm/realm.dart';
import 'models/osu_realm_models.dart';

const _kRealmPath = r'D:\osu!lazer\client.realm';

void main() {
  runApp(const OsuBeatmapApp());
}

class OsuBeatmapApp extends StatelessWidget {
  const OsuBeatmapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'osu! Beatmap Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pinkAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const BeatmapListPage(),
    );
  }
}

// ── 圖譜列表頁面 ──────────────────────────────────────────────────────────────

class BeatmapListPage extends StatefulWidget {
  const BeatmapListPage({super.key});

  @override
  State<BeatmapListPage> createState() => _BeatmapListPageState();
}

class _BeatmapListPageState extends State<BeatmapListPage> {
  Realm? _realm;
  List<BeatmapSetInfo> _beatmapSets = [];
  String? _error;
  bool _loading = false;
  bool _exporting = false;
  bool _importing = false;
  String _searchQuery = '';

  /// 所有要傳入 Realm 的 Schema 物件
  static final _schemas = [
    BeatmapSetInfo.schema,
    BeatmapInfo.schema,
    BeatmapMetadata.schema,
    RulesetInfo.schema,
    RealmUser.schema,
  ];

  @override
  void initState() {
    super.initState();
    _loadRealm();
  }

  @override
  void dispose() {
    _realm?.close();
    super.dispose();
  }

  // ── 載入 Realm ─────────────────────────────────────────────────────────────

  Future<void> _loadRealm() async {
    setState(() {
      _loading = true;
      _error = null;
      _beatmapSets = [];
    });

    try {
      _realm?.close();
      _realm = null;
      final realm = await _openRealm(_kRealmPath);
      final sets =
          realm.all<BeatmapSetInfo>().where((s) => !s.deletePending).toList()
            ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      setState(() {
        _realm = realm;
        _beatmapSets = sets;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 自動偵測 schema version 並以唯讀方式開啟 client.realm
  Future<Realm> _openRealm(String path) async {
    if (!File(path).existsSync()) {
      throw Exception('找不到 Realm 檔案：$path');
    }

    String lastError = '';

    // ── 步驟 1：嘗試 version=49，從錯誤訊息解析實際版本 ──────────────────────
    try {
      return Realm(
        Configuration.local(
          _schemas,
          path: path,
          isReadOnly: true,
          schemaVersion: 49,
        ),
      );
    } on RealmException catch (e) {
      lastError = e.toString();

      // 從錯誤訊息擷取所有數字，嘗試當作 schema version 重開
      final candidates =
          RegExp(r'\b(\d{1,3})\b')
              .allMatches(lastError)
              .map((m) => int.tryParse(m.group(0)!))
              .nonNulls
              .where((n) => n > 0 && n < 300)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a)); // 由大到小嘗試

      for (final v in candidates) {
        try {
          return Realm(
            Configuration.local(
              _schemas,
              path: path,
              isReadOnly: true,
              schemaVersion: v,
            ),
          );
        } catch (_) {}
      }
    }

    // ── 步驟 2：退而求其次，依序嘗試常見 osu!lazer schema 版本 ──────────────
    for (final v in _likelyVersions) {
      try {
        return Realm(
          Configuration.local(
            _schemas,
            path: path,
            isReadOnly: true,
            schemaVersion: v,
          ),
        );
      } catch (_) {}
    }

    throw Exception('無法開啟 Realm 檔案（嘗試所有已知 schema 版本皆失敗）。\n\n$lastError');
  }

  // ── 匯出 CSV ───────────────────────────────────────────────────────────────

  static const _statusLabel = {
    -3: 'Unknown',
    -2: '墓地',
    -1: 'WIP',
    0: 'Pending',
    1: 'Ranked',
    2: 'Approved',
    3: 'Qualified',
    4: 'Loved',
  };

  Future<void> _exportCsv() async {
    if (_beatmapSets.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final sb = StringBuffer();
      // UTF-8 BOM，讓 Excel 正確辨識中文
      sb.write('\uFEFF');
      sb.writeln(
        _csvRow([
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
        ]),
      );

      for (final s in _beatmapSets) {
        final meta = s.beatmaps.isNotEmpty ? s.beatmaps.first.metadata : null;
        final stars =
            s.beatmaps.map((b) => b.starRating).where((r) => r > 0).toList()
              ..sort();
        final modes = s.beatmaps
            .map((b) => b.ruleset?.shortName ?? '?')
            .toSet()
            .join('/');
        final bpms =
            s.beatmaps.map((b) => b.bpm).where((b) => b > 0).toSet().toList()
              ..sort();
        final bpmStr = bpms.isEmpty
            ? ''
            : bpms.length == 1
            ? bpms.first.toStringAsFixed(0)
            : '${bpms.first.toStringAsFixed(0)}-${bpms.last.toStringAsFixed(0)}';

        sb.writeln(
          _csvRow([
            s.onlineID.toString(),
            meta?.title ?? '',
            meta?.titleUnicode ?? '',
            meta?.artist ?? '',
            meta?.artistUnicode ?? '',
            meta?.author?.username ?? '',
            _statusLabel[s.status] ?? s.status.toString(),
            s.beatmaps.length.toString(),
            modes,
            stars.isEmpty ? '' : stars.first.toStringAsFixed(2),
            stars.isEmpty ? '' : stars.last.toStringAsFixed(2),
            bpmStr,
            s.dateAdded.toLocal().toIso8601String().split('T').first,
            s.dateSubmitted?.toLocal().toIso8601String().split('T').first ?? '',
          ]),
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:\.]'), '-')
          .substring(0, 19);
      final file = File('${dir.path}/osu_beatmaps_$ts.csv');
      await file.writeAsString(sb.toString(), flush: true);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('匯出完成'),
          content: SelectableText(
            '已儲存 ${_beatmapSets.length} 筆圖譜集至：\n${file.path}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯出失敗：$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 將一列欄位轉換為 CSV 格式（自動跳脫雙引號）
  String _csvRow(List<String> fields) {
    return fields.map((f) => '"${f.replaceAll('"', '""')}"').join(',');
  }

  // ── 匯入 CSV ───────────────────────────────────────────────────────────────

  Future<void> _importCsv() async {
    setState(() => _importing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final csvFiles =
          dir
              .listSync()
              .whereType<File>()
              .where(
                (f) =>
                    f.path.endsWith('.csv') &&
                    f.uri.pathSegments.last.startsWith('osu_beatmaps_'),
              )
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path)); // 最新在最上

      if (!mounted) return;
      if (csvFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到已匯出的 CSV 檔案，請先匯出至少一次')),
        );
        return;
      }

      final selected = await showDialog<File>(
        context: context,
        builder: (_) => _CsvPickerDialog(files: csvFiles),
      );
      if (selected == null || !mounted) return;

      final content = await selected.readAsString();
      final rows = _parseCsvContent(content);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _CsvImportPage(
            filename: selected.uri.pathSegments.last,
            rows: rows,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯入失敗：$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  static List<_CsvRow> _parseCsvContent(String content) {
    final text = content.startsWith('\uFEFF') ? content.substring(1) : content;
    final lines = text
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return [];
    final headers = _splitCsvLine(lines[0]);
    final rows = <_CsvRow>[];
    for (final line in lines.skip(1)) {
      final fields = _splitCsvLine(line);
      if (fields.isEmpty) continue;
      final map = <String, String>{};
      for (var i = 0; i < headers.length && i < fields.length; i++) {
        map[headers[i]] = fields[i];
      }
      rows.add(_CsvRow(map));
    }
    return rows;
  }

  static List<String> _splitCsvLine(String line) {
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

  /// 依可能性由高到低排列的 osu!lazer schema 版本備選清單
  static final _likelyVersions = [
    ...List.generate(200, (i) => 200 - i), // 200 → 1
  ];

  // ── 搜尋過濾 ───────────────────────────────────────────────────────────────

  List<BeatmapSetInfo> get _filtered {
    if (_searchQuery.isEmpty) return _beatmapSets;
    final q = _searchQuery.toLowerCase();
    return _beatmapSets.where((s) {
      if (s.beatmaps.isEmpty) return false;
      final meta = s.beatmaps.first.metadata;
      if (meta == null) return false;
      return (meta.title?.toLowerCase().contains(q) ?? false) ||
          (meta.artist?.toLowerCase().contains(q) ?? false) ||
          (meta.titleUnicode?.toLowerCase().contains(q) ?? false) ||
          (meta.artistUnicode?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('osu! Beatmap Viewer'),
        actions: [
          if (!_loading && _beatmapSets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('共 ${_beatmapSets.length} 個圖譜集')),
            ),
          if (!_loading && _beatmapSets.isNotEmpty)
            _exporting
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: '匯出 CSV',
                    onPressed: _exportCsv,
                  ),
          _importing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.upload_file),
                  tooltip: '從 CSV 匯入',
                  onPressed: _importCsv,
                ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新載入',
            onPressed: _loading ? null : _loadRealm,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在讀取 client.realm …'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                '讀取失敗',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
                onPressed: _loadRealm,
              ),
            ],
          ),
        ),
      );
    }

    if (_beatmapSets.isEmpty) {
      return const Center(child: Text('沒有找到圖譜集'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜尋標題、藝術家…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filtered.length,
            itemBuilder: (ctx, i) => _BeatmapSetTile(set: _filtered[i]),
          ),
        ),
      ],
    );
  }
}

// ── 圖譜集清單項目 ─────────────────────────────────────────────────────────────

class _BeatmapSetTile extends StatelessWidget {
  final BeatmapSetInfo set;

  const _BeatmapSetTile({required this.set});

  static const _statusLabel = {
    -3: 'Unknown',
    -2: '墓地',
    -1: 'WIP',
    0: 'Pending',
    1: 'Ranked',
    2: 'Approved',
    3: 'Qualified',
    4: 'Loved',
  };

  @override
  Widget build(BuildContext context) {
    final meta = set.beatmaps.isNotEmpty ? set.beatmaps.first.metadata : null;
    final title = (meta?.titleUnicode?.isNotEmpty == true)
        ? meta!.titleUnicode!
        : (meta?.title ?? '（未知標題）');
    final artist = (meta?.artistUnicode?.isNotEmpty == true)
        ? meta!.artistUnicode!
        : (meta?.artist ?? '（未知藝術家）');

    final stars =
        set.beatmaps.map((b) => b.starRating).where((s) => s > 0).toList()
          ..sort();

    final statusText = _statusLabel[set.status] ?? '?';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: _ModeIcon(beatmaps: set.beatmaps),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$artist  ·  $statusText  ·  ${set.beatmaps.length} 難度',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: stars.isEmpty
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '★ ${stars.last.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (stars.length > 1)
                    Text(
                      '${stars.first.toStringAsFixed(2)} – ${stars.last.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                    ),
                ],
              ),
        onTap: () =>
            _showDetails(context, set.beatmaps.toList(), title, artist),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    List<BeatmapInfo> beatmaps,
    String title,
    String artist,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (_) =>
          _BeatmapDetailSheet(beatmaps: beatmaps, title: title, artist: artist),
    );
  }
}

// ── 難度清單 Bottom Sheet ──────────────────────────────────────────────────────

class _BeatmapDetailSheet extends StatelessWidget {
  final List<BeatmapInfo> beatmaps;
  final String title;
  final String artist;

  const _BeatmapDetailSheet({
    required this.beatmaps,
    required this.title,
    required this.artist,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...beatmaps]
      ..sort((a, b) => a.starRating.compareTo(b.starRating));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1.0,
      maxChildSize: 1.0,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(artist, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              itemCount: sorted.length,
              itemBuilder: (_, i) => _DifficultyTile(beatmap: sorted[i]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 單一難度項目 ───────────────────────────────────────────────────────────────

class _DifficultyTile extends StatelessWidget {
  final BeatmapInfo beatmap;

  const _DifficultyTile({required this.beatmap});

  String _formatDuration(double ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    return '${m}m ${s % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final mode = beatmap.ruleset?.shortName ?? '?';

    return ListTile(
      leading: Text(
        '★${beatmap.starRating.toStringAsFixed(2)}',
        style: const TextStyle(color: Colors.amber, fontSize: 12),
      ),
      title: Text(beatmap.difficultyName ?? '（未命名）'),
      subtitle: Text(
        '[$mode]  BPM ${beatmap.bpm.toStringAsFixed(0)}'
        '  ${_formatDuration(beatmap.length)}',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

// ── 遊戲模式 Icon ──────────────────────────────────────────────────────────────

class _ModeIcon extends StatelessWidget {
  final Iterable<BeatmapInfo> beatmaps;

  const _ModeIcon({required this.beatmaps});

  @override
  Widget build(BuildContext context) {
    final modes = beatmaps.map((b) => b.ruleset?.shortName ?? '?').toSet();
    final label = modes.length == 1 ? modes.first : '♫';
    return CircleAvatar(
      radius: 18,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ── CSV 匯入：資料類別 ──────────────────────────────────────────────────────────

class _CsvRow {
  final Map<String, String> data;
  const _CsvRow(this.data);
  String operator [](String key) => data[key] ?? '';
}

// ── CSV 檔案選擇對話框 ─────────────────────────────────────────────────────────

class _CsvPickerDialog extends StatelessWidget {
  final List<File> files;

  const _CsvPickerDialog({required this.files});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('選擇 CSV 檔案'),
      content: SizedBox(
        width: 480,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: files.length,
          itemBuilder: (_, i) {
            final name = files[i].uri.pathSegments.last;
            return ListTile(
              leading: const Icon(Icons.table_chart),
              title: Text(name),
              onTap: () => Navigator.pop(context, files[i]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

// ── CSV 匯入頁面 ──────────────────────────────────────────────────────────────

class _CsvImportPage extends StatefulWidget {
  final String filename;
  final List<_CsvRow> rows;

  const _CsvImportPage({required this.filename, required this.rows});

  @override
  State<_CsvImportPage> createState() => _CsvImportPageState();
}

class _CsvImportPageState extends State<_CsvImportPage> {
  String _search = '';

  List<_CsvRow> get _filtered {
    if (_search.isEmpty) return widget.rows;
    final q = _search.toLowerCase();
    return widget.rows
        .where(
          (r) =>
              r['Title'].toLowerCase().contains(q) ||
              r['TitleUnicode'].toLowerCase().contains(q) ||
              r['Artist'].toLowerCase().contains(q) ||
              r['ArtistUnicode'].toLowerCase().contains(q) ||
              r['Creator'].toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.filename,
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜尋標題、藝術家、製圖者…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                _search.isNotEmpty
                    ? '共 ${widget.rows.length} 筆  (篩選後 ${_filtered.length} 筆)'
                    : '共 ${widget.rows.length} 筆',
              ),
            ),
          ),
        ],
      ),
      body: _filtered.isEmpty
          ? const Center(child: Text('沒有符合的結果'))
          : ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) => _CsvRowTile(row: _filtered[i]),
            ),
    );
  }
}

// ── CSV 圖譜集列表項目 ─────────────────────────────────────────────────────────

class _CsvRowTile extends StatelessWidget {
  final _CsvRow row;

  const _CsvRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final title = row['TitleUnicode'].isNotEmpty
        ? row['TitleUnicode']
        : row['Title'].isNotEmpty
        ? row['Title']
        : '（未知標題）';
    final artist = row['ArtistUnicode'].isNotEmpty
        ? row['ArtistUnicode']
        : row['Artist'].isNotEmpty
        ? row['Artist']
        : '（未知藝術家）';
    final mode = row['模式'];
    final status = row['Status'];
    final diffCount = row['難度數'];
    final starLow = row['最低星數'];
    final starHigh = row['最高星數'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            mode.isNotEmpty ? mode : '♫',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$artist  ·  $status  ·  $diffCount 難度',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: starHigh.isNotEmpty
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '★ $starHigh',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (starLow != starHigh)
                    Text(
                      '$starLow – $starHigh',
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                    ),
                ],
              )
            : null,
        onTap: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (artist != '（未知藝術家）') Text('藝術家：$artist'),
                if (row['Creator'].isNotEmpty) Text('製圖者：${row['Creator']}'),
                Text('狀態：$status'),
                Text('難度數：$diffCount'),
                if (mode.isNotEmpty) Text('模式：$mode'),
                if (row['BPM'].isNotEmpty) Text('BPM：${row['BPM']}'),
                if (starHigh.isNotEmpty) Text('星數：$starLow – $starHigh'),
                if (row['OnlineID'].isNotEmpty && row['OnlineID'] != '0')
                  Text('Online ID：${row['OnlineID']}'),
                if (row['加入日期'].isNotEmpty) Text('加入日期：${row['加入日期']}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
