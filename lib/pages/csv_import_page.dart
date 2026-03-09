import 'package:flutter/material.dart';
import '../models/csv_row.dart';
import '../services/download_service.dart';
import '../widgets/csv_row_tile.dart';

class CsvImportPage extends StatefulWidget {
  final String filename;
  final List<CsvRow> rows;

  const CsvImportPage({super.key, required this.filename, required this.rows});

  @override
  State<CsvImportPage> createState() => _CsvImportPageState();
}

class _CsvImportPageState extends State<CsvImportPage> {
  String _search = '';

  Future<void> _enqueueAll() async {
    final toDownload = _filtered
        .where((r) => (int.tryParse(r['OnlineID']) ?? 0) > 0)
        .toList();
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

    for (final r in toDownload) {
      final id = int.tryParse(r['OnlineID']) ?? 0;
      final title = r['TitleUnicode'].isNotEmpty
          ? r['TitleUnicode']
          : r['Title'];
      DownloadService.instance.enqueue(id, title);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已將 ${toDownload.length} 個圖譜集加入下載佇列')),
    );
  }

  List<CsvRow> get _filtered {
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
          IconButton(
            icon: const Icon(Icons.download_for_offline),
            tooltip: '批量下載全部圖譜（依篩選）',
            onPressed: _enqueueAll,
          ),
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
              itemBuilder: (_, i) => CsvRowTile(row: _filtered[i]),
            ),
    );
  }
}
