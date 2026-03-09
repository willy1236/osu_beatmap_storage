import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:realm/realm.dart';
import '../constants.dart';
import '../models/download_job.dart';
import '../models/osu_realm_models.dart';
import '../services/download_service.dart';
import '../services/prefs_service.dart';
import '../services/realm_service.dart';
import '../utils/csv_parser.dart';
import '../widgets/beatmap_set_tile.dart';
import '../widgets/csv_picker_dialog.dart';
import 'csv_import_page.dart';
import 'download_queue_page.dart';
import 'replay_list_page.dart';

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
  bool _batchEnqueuing = false;
  String _searchQuery = '';
  String _osuDir = kDefaultOsuDir;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final isFirst = !(await PrefsService.hasOsuDir());
    if (isFirst) {
      // 首次啟動：等 widget tree 就緒後直接彈出選取器
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pickRealmFile(isFirstLaunch: true),
      );
      setState(() => _loading = false);
      return;
    }
    final path = await PrefsService.getOsuDir();
    setState(() => _osuDir = path);
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
      final realm = await RealmService.open(p.join(_osuDir, 'client.realm'));
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

  // ── 選取 Realm 路徑 ────────────────────────────────────────────────────────

  Future<void> _pickRealmFile({bool isFirstLaunch = false}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '選取 client.realm 檔案',
      type: FileType.custom,
      allowedExtensions: ['realm'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      // 首次啟動取消選取：顯示提示，讓使用者知道之後可以再選
      if (isFirstLaunch && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('尚未選取 client.realm，請點擊右上角資料夾圖示選取'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    final path = result.files.single.path;
    if (path == null || !mounted) return;
    await PrefsService.setOsuDir(p.dirname(path));
    setState(() => _osuDir = p.dirname(path));
    _loadRealm();
  }

  // ── 匯出 CSV ───────────────────────────────────────────────────────────────

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
            kStatusLabel[s.status] ?? s.status.toString(),
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

  static String _csvRow(List<String> fields) =>
      fields.map((f) => '"${f.replaceAll('"', '""')}"').join(',');

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
            ..sort((a, b) => b.path.compareTo(a.path));

      if (!mounted) return;
      if (csvFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到已匯出的 CSV 檔案，請先匯出至少一次')),
        );
        return;
      }

      final selected = await showDialog<File>(
        context: context,
        builder: (_) => CsvPickerDialog(files: csvFiles),
      );
      if (selected == null || !mounted) return;

      final content = await selected.readAsString();
      final rows = CsvParser.parse(content);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CsvImportPage(
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

  // ── 批量下載 ───────────────────────────────────────────────────────────────

  Future<void> _enqueueAll() async {
    final toDownload = _filtered.where((s) => s.onlineID > 0).toList();
    if (toDownload.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('批量下載'),
        content: Text(
          '確定要將 ${toDownload.length} 個圖譜集加入下載佇列？\n'
          '下載位置：${DownloadService.downloadsPath}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _batchEnqueuing = true);
    try {
      for (final s in toDownload) {
        final meta = s.beatmaps.isNotEmpty ? s.beatmaps.first.metadata : null;
        final title = (meta?.titleUnicode?.isNotEmpty == true)
            ? meta!.titleUnicode!
            : (meta?.title ?? '');
        DownloadService.instance.enqueue(s.onlineID, title);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已將 ${toDownload.length} 個圖譜集加入下載佇列')),
      );
    } finally {
      if (mounted) setState(() => _batchEnqueuing = false);
    }
  }

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
          if (!_loading && _beatmapSets.isNotEmpty)
            _batchEnqueuing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.download_for_offline),
                    tooltip: '批量下載全部圖譜',
                    onPressed: _enqueueAll,
                  ),
          ListenableBuilder(
            listenable: DownloadService.instance,
            builder: (_, _) {
              final pending = DownloadService.instance.jobs
                  .where(
                    (j) =>
                        j.status == DownloadStatus.queued ||
                        j.status == DownloadStatus.downloading,
                  )
                  .length;
              return IconButton(
                icon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: const Icon(Icons.queue_music),
                ),
                tooltip: '下載佇列',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DownloadQueuePage()),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: '回放列表',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReplayListPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '選取 client.realm 路徑',
            onPressed: _pickRealmFile,
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在讀取…\n$_osuDir',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
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
                icon: const Icon(Icons.folder_open),
                label: const Text('選取 client.realm'),
                onPressed: _pickRealmFile,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
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

    // 首次啟動：尚未選取路徑、也沒有資料
    if (_beatmapSets.isEmpty && _osuDir == kDefaultOsuDir) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 72, color: Colors.grey),
              const SizedBox(height: 20),
              const Text(
                '歡迎使用 osu! Beatmap Storage',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '請選取 osu!lazer 的 client.realm 檔案\n（通常位於 D:\\osu!lazer\\client.realm）',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('選取 client.realm'),
                onPressed: _pickRealmFile,
              ),
            ],
          ),
        ),
      );
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
            itemBuilder: (ctx, i) => BeatmapSetTile(set: _filtered[i]),
          ),
        ),
      ],
    );
  }
}
