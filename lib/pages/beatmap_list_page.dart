import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:realm/realm.dart';
import '../constants.dart';
import '../models/beatmap_set_row.dart';
import '../models/cloud_entry.dart';
import '../models/download_job.dart';
import '../models/osu_realm_models.dart';
import '../services/auth_service.dart';
import '../services/auto_upload_service.dart';
import '../services/cloud_list_service.dart';
import '../services/cloud_presence_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/download_service.dart';
import '../services/local_library_service.dart';
import '../services/osu_dir_detector.dart';
import '../services/prefs_service.dart';
import '../services/realm_service.dart';
import '../utils/beatmap_csv.dart';
import '../utils/csv_parser.dart';
import '../widgets/beatmap_set_tile.dart';
import '../widgets/csv_picker_dialog.dart';
import 'cloud_list_page.dart';
import 'csv_import_page.dart';
import 'download_queue_page.dart';

class BeatmapListPage extends StatefulWidget {
  const BeatmapListPage({super.key});

  @override
  State<BeatmapListPage> createState() => _BeatmapListPageState();
}

class _BeatmapListPageState extends State<BeatmapListPage> {
  Realm? _realm;
  List<BeatmapSetInfo> _beatmapSets = [];

  /// 與 [_beatmapSets] 同順序，載入時一次算好的顯示資料
  List<BeatmapSetRow> _rows = [];

  /// 依 [_searchQuery] 過濾後的 [_rows]，只在資料或搜尋字串改變時重算
  List<BeatmapSetRow> _filtered = [];
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
      final detected = await OsuDirDetector.detect();
      if (detected != null) {
        await PrefsService.setOsuDir(detected);
        if (!mounted) return;
        setState(() => _osuDir = detected);
        _loadRealm(autoUpload: true);
        return;
      }
      if (!mounted) return;
      // 首次啟動且找不到：等 widget tree 就緒後直接彈出選取器
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pickRealmFile(isFirstLaunch: true),
      );
      setState(() => _loading = false);
      return;
    }
    final path = await PrefsService.getOsuDir();
    setState(() => _osuDir = path);
    _loadRealm(autoUpload: true);
  }

  @override
  void dispose() {
    _realm?.close();
    super.dispose();
  }

  // ── 載入 Realm ─────────────────────────────────────────────────────────────

  /// [autoUpload] 只有程式開啟時的那次載入為 true；那次失敗後重新載入或重選路徑都不觸發自動上傳
  Future<void> _loadRealm({bool autoUpload = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _beatmapSets = [];
      _rows = [];
      _filtered = [];
    });
    try {
      _realm?.close();
      _realm = null;
      final realm = await RealmService.open(p.join(_osuDir, 'client.realm'));
      final sets =
          realm.all<BeatmapSetInfo>().where((s) => !s.deletePending).toList()
            ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      // 不等待：重新載入或重選路徑時順便更新「已在雲端」標示；程式開啟時那次由登入還原觸發，不重複讀
      if (!autoUpload) CloudPresenceService.instance.refresh();
      LocalLibraryService.instance.setOnlineIds({
        for (final s in sets)
          if (s.onlineID > 0) s.onlineID,
      });
      final rows = sets.map(BeatmapSetRow.from).toList();
      setState(() {
        _realm = realm;
        _beatmapSets = sets;
        _rows = rows;
        _filtered = _applyFilter(rows, _searchQuery);
        _loading = false;
      });
      if (autoUpload) {
        // 不等待：靜默執行，進度與失敗由既有的雲端狀態列顯示
        AutoUploadService.instance.runOnStartup(
          () => sets.map(toCloudEntry).toList(),
        );
      }
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
      sb.writeln(_csvRow(kCsvHeader));

      for (final s in _beatmapSets) {
        sb.writeln(_csvRow(csvFieldsOf(s)));
      }

      final appDir = p.dirname(Platform.resolvedExecutable);
      final csvDir = Directory(p.join(appDir, 'csv_exports'));
      await csvDir.create(recursive: true);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:\.]'), '-')
          .substring(0, 19);
      final file = File(p.join(csvDir.path, 'osu_beatmaps_$ts.csv'));
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

  // ── 上傳到雲端 ─────────────────────────────────────────────────────────────

  Future<void> _uploadToCloud() async {
    if (_beatmapSets.isEmpty || CloudSyncService.instance.uploading) return;
    final entries = _beatmapSets.map(toCloudEntry).toList();
    final result = await CloudSyncService.instance.upload(
      entries,
      trigger: 'manual',
    );
    if (!mounted) return;
    // 失敗只顯示在狀態區（CloudSyncService.lastError），不彈窗
    final text = switch (result.status) {
      CloudSyncStatus.success =>
        '已上傳到雲端：新增 ${result.inserted}、更新 ${result.updated}'
            '${result.skipped > 0 ? '、略過 ${result.skipped}' : ''}',
      CloudSyncStatus.rateLimited => '請稍後再試',
      _ => null,
    };
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  // ── 雲端清單 ───────────────────────────────────────────────────────────────

  void _openCloudList() {
    final localIds = {
      for (final s in _beatmapSets)
        if (s.onlineID > 0) s.onlineID,
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CloudListPage(
          title: '雲端清單',
          loader: CloudListService.instance.fetchMine,
          localIds: localIds,
          canDelete: true,
          onDelete: CloudListService.instance.deleteSome,
          onClear: CloudListService.instance.clearAll,
        ),
      ),
    );
  }

  /// AppBar 下方的雲端上傳狀態：上傳中顯示細進度條，失敗時顯示一行說明
  Widget _cloudStatusStrip() {
    return ListenableBuilder(
      listenable: CloudSyncService.instance,
      builder: (context, _) {
        final cloud = CloudSyncService.instance;
        final progress = cloud.progress;
        if (progress != null) {
          return LinearProgressIndicator(
            value: progress.sent == 0 ? null : progress.fraction,
            minHeight: 3,
          );
        }
        final error = cloud.lastError;
        if (error == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.errorContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            error,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        );
      },
    );
  }

  // ── 匯入 CSV ───────────────────────────────────────────────────────────────

  Future<void> _importCsv() async {
    setState(() => _importing = true);
    try {
      final appDir = p.dirname(Platform.resolvedExecutable);
      final csvDir = Directory(p.join(appDir, 'csv_exports'));
      final csvFiles = csvDir.existsSync()
          ? (csvDir
                .listSync()
                .whereType<File>()
                .where(
                  (f) =>
                      f.path.endsWith('.csv') &&
                      p.basename(f.path).startsWith('osu_beatmaps_'),
                )
                .toList()
              ..sort((a, b) => b.path.compareTo(a.path)))
          : <File>[];

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
      for (final s in toDownload.map((r) => r.set)) {
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

  static List<BeatmapSetRow> _applyFilter(
    List<BeatmapSetRow> rows,
    String query,
  ) {
    if (query.isEmpty) return rows;
    final q = query.toLowerCase();
    return rows.where((r) => r.searchText.contains(q)).toList();
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
          ListenableBuilder(
            listenable: Listenable.merge([
              AuthService.instance,
              CloudSyncService.instance,
            ]),
            builder: (_, _) {
              if (!AuthService.instance.isLoggedIn ||
                  _loading ||
                  _beatmapSets.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.cloud_upload),
                tooltip: '上傳到雲端',
                onPressed: CloudSyncService.instance.uploading
                    ? null
                    : _uploadToCloud,
              );
            },
          ),
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (_, _) => AuthService.instance.isLoggedIn
                ? IconButton(
                    icon: const Icon(Icons.cloud_queue),
                    tooltip: '雲端清單',
                    onPressed: _openCloudList,
                  )
                : const SizedBox.shrink(),
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
      body: Column(
        children: [
          _cloudStatusStrip(),
          Expanded(child: _buildBody()),
        ],
      ),
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
            onChanged: (v) => setState(() {
              _searchQuery = v;
              _filtered = _applyFilter(_rows, v);
            }),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filtered.length,
            // 每列等高：拖捲軸大跨度跳轉時不必逐列量高度
            prototypeItem: _filtered.isEmpty
                ? null
                : BeatmapSetTile(row: _filtered.first),
            itemBuilder: (ctx, i) => BeatmapSetTile(row: _filtered[i]),
          ),
        ),
      ],
    );
  }
}
