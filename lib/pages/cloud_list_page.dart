import 'package:flutter/material.dart';

import '../models/cloud_entry.dart';
import '../services/cloud_list_service.dart';
import '../services/download_service.dart';
import '../widgets/csv_row_tile.dart';

/// 依搜尋字串（標題、藝術家、製圖者，規則同 `CsvImportPage`）與「只看本機缺」過濾
List<CloudEntry> filterCloudEntries(
  List<CloudEntry> entries, {
  String query = '',
  bool onlyMissing = false,
  Set<int> localIds = const {},
}) {
  final q = query.toLowerCase();
  return entries.where((e) {
    if (onlyMissing && localIds.contains(e.onlineId)) return false;
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) ||
        e.titleUnicode.toLowerCase().contains(q) ||
        e.artist.toLowerCase().contains(q) ||
        e.artistUnicode.toLowerCase().contains(q) ||
        e.creator.toLowerCase().contains(q);
  }).toList();
}

/// 雲端清單頁。[loader] 是清單來源（T-08 傳入分享清單的讀取），
/// [localIds] 是開啟當下本機已有的 OnlineID。
class CloudListPage extends StatefulWidget {
  const CloudListPage({
    super.key,
    required this.title,
    required this.loader,
    required this.localIds,
  });

  final String title;
  final Future<CloudListResult> Function() loader;
  final Set<int> localIds;

  @override
  State<CloudListPage> createState() => _CloudListPageState();
}

class _CloudListPageState extends State<CloudListPage> {
  CloudListResult? _result;
  bool _loading = true;
  String _search = '';
  bool _onlyMissing = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.loader();
    if (!mounted) return;
    setState(() {
      _result = r;
      _loading = false;
      _selected.clear();
    });
  }

  List<CloudEntry> get _filtered => filterCloudEntries(
    _result?.entries ?? const [],
    query: _search,
    onlyMissing: _onlyMissing,
    localIds: widget.localIds,
  );

  void _selectAllMissing() {
    setState(() {
      _selected
        ..clear()
        ..addAll(
          _filtered
              .where((e) => !widget.localIds.contains(e.onlineId))
              .map((e) => e.onlineId),
        );
    });
  }

  void _download() {
    final items = (_result?.entries ?? const <CloudEntry>[])
        .where((e) => _selected.contains(e.onlineId))
        .map(
          (e) => (
            onlineID: e.onlineId,
            title: e.titleUnicode.isNotEmpty ? e.titleUnicode : e.title,
          ),
        )
        .toList();
    if (items.isEmpty) return;
    DownloadService.instance.enqueueAll(items);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已將 ${items.length} 個圖譜集加入下載佇列')));
    setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final ok = result != null && result.ok;
    final total = result?.entries.length ?? 0;
    final missing = ok
        ? result.entries
              .where((e) => !widget.localIds.contains(e.onlineId))
              .length
        : 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: ok
            ? PreferredSize(
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
              )
            : null,
        actions: [
          if (ok) ...[
            FilterChip(
              label: const Text('只看本機缺'),
              selected: _onlyMissing,
              onSelected: (v) => setState(() => _onlyMissing = v),
            ),
            TextButton(
              onPressed: _selectAllMissing,
              child: const Text('全選本機缺的'),
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: '下載勾選的圖譜（${_selected.length}）',
              onPressed: _selected.isEmpty ? null : _download,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('共 $total 筆・本機缺 $missing 筆')),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final result = _result!;
    if (!result.ok) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              SelectableText(result.message ?? '讀取失敗'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    if (result.entries.isEmpty) {
      return const Center(child: Text('雲端清單是空的'));
    }
    final list = _filtered;
    if (list.isEmpty) return const Center(child: Text('沒有符合的結果'));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final e = list[i];
        final have = widget.localIds.contains(e.onlineId);
        return CsvRowTile(
          key: ValueKey(e.onlineId),
          row: e.toCsvRow(),
          selected: _selected.contains(e.onlineId),
          onSelectedChanged: (v) => setState(() {
            if (v == true) {
              _selected.add(e.onlineId);
            } else {
              _selected.remove(e.onlineId);
            }
          }),
          badge: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text(have ? '本機有' : '本機缺'),
              visualDensity: VisualDensity.compact,
              backgroundColor: have
                  ? Colors.green.shade100
                  : Colors.orange.shade100,
              labelStyle: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
        );
      },
    );
  }
}
