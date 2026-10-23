import 'package:flutter/material.dart';

import '../models/cloud_entry.dart';
import '../services/cloud_list_service.dart';
import '../services/download_service.dart';
import '../widgets/csv_row_tile.dart';

/// 刪除確認對話框都要帶的提示
const kCloudDeleteHint = '本機還有的圖譜，下次上傳會再出現。';

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
    this.canDelete = false,
    this.onDelete,
    this.onClear,
    this.extraActionsBuilder,
    this.selectionActionsBuilder,
    this.canRetry,
  });

  final String title;
  final Future<CloudListResult> Function() loader;
  final Set<int> localIds;

  /// 可刪除模式（自己的清單）；別人的分享清單不傳。需同時提供 [onDelete] 與 [onClear]
  final bool canDelete;
  final Future<CloudDeleteResult> Function(List<int> onlineIds)? onDelete;
  final Future<CloudDeleteResult> Function()? onClear;

  /// 讀取成功後額外放在 AppBar 最右邊的動作（例如分享清單的「複製到我的雲端清單」）
  final List<Widget> Function(CloudListResult result)? extraActionsBuilder;

  /// 依目前勾選的項目產生的 AppBar 動作（例如「推送給好友」）；放在下載按鈕之後
  final List<Widget> Function(List<CloudEntry> selected)?
  selectionActionsBuilder;

  /// 讀取失敗時是否顯示「重試」；預設一律顯示（例如連結已失效時重試沒有意義）
  final bool Function(CloudListResult result)? canRetry;

  @override
  State<CloudListPage> createState() => _CloudListPageState();
}

class _CloudListPageState extends State<CloudListPage> {
  CloudListResult? _result;
  bool _loading = true;
  String _search = '';
  bool _onlyMissing = false;
  bool _deleting = false;
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

  /// 篩選改變後移除被藏起來的勾選，下載與刪除只作用在看得到的項目
  void _dropHiddenSelection() =>
      _selected.retainAll(_filtered.map((e) => e.onlineId));

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

  Future<bool> _confirm({
    required String title,
    required String content,
    bool danger = false,
    String action = '刪除',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _deleteSelected() async {
    final del = widget.onDelete;
    if (del == null || _selected.isEmpty || _deleting) return;
    final ids = _selected.toList();
    if (!await _confirm(
      title: '刪除雲端紀錄',
      content: '確定要從雲端清單刪除 ${ids.length} 個圖譜集？\n$kCloudDeleteHint',
    )) {
      return;
    }
    setState(() => _deleting = true);
    final r = await del(ids);
    if (!mounted) return;
    setState(() {
      _deleting = false;
      if (r.ok) {
        final gone = ids.toSet();
        _result = CloudListResult(
          _result!.status,
          entries: _result!.entries
              .where((e) => !gone.contains(e.onlineId))
              .toList(),
          ownerUsername: _result!.ownerUsername,
        );
        _selected.removeAll(gone);
      }
    });
    _snack(r.ok ? '已刪除 ${r.deleted} 個圖譜集' : (r.message ?? '刪除失敗'));
  }

  Future<void> _clearAll() async {
    final clear = widget.onClear;
    final total = _result?.entries.length ?? 0;
    if (clear == null || total == 0 || _deleting) return;
    if (!await _confirm(
      title: '清空雲端清單',
      content: '雲端清單共 $total 個圖譜集，將全部刪除。\n$kCloudDeleteHint',
      action: '繼續',
    )) {
      return;
    }
    if (!await _confirm(
      title: '再次確認',
      content: '真的要清空整份雲端清單嗎？此操作無法復原，分享連結看到的清單也會跟著清空。',
      danger: true,
      action: '清空',
    )) {
      return;
    }
    setState(() => _deleting = true);
    final r = await clear();
    if (!mounted) return;
    setState(() {
      _deleting = false;
      if (r.ok) {
        _result = CloudListResult(
          _result!.status,
          ownerUsername: _result!.ownerUsername,
        );
        _selected.clear();
      }
    });
    _snack(r.ok ? '已清空雲端清單（刪除 ${r.deleted} 個）' : (r.message ?? '清空失敗'));
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
        title: Text(
          (result?.ownerUsername ?? '').isNotEmpty
              ? '「${result!.ownerUsername}」的清單'
              : widget.title,
        ),
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
                    onChanged: (v) => setState(() {
                      _search = v;
                      _dropHiddenSelection();
                    }),
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新整理',
            onPressed: _loading ? null : _load,
          ),
          if (ok) ...[
            FilterChip(
              label: const Text('只看本機缺'),
              selected: _onlyMissing,
              onSelected: (v) => setState(() {
                _onlyMissing = v;
                _dropHiddenSelection();
              }),
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
            ...?widget.selectionActionsBuilder?.call(
              result.entries
                  .where((e) => _selected.contains(e.onlineId))
                  .toList(),
            ),
            if (widget.canDelete) ...[
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '刪除勾選的圖譜（${_selected.length}）',
                onPressed: _selected.isEmpty || _deleting
                    ? null
                    : _deleteSelected,
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: '清空雲端清單',
                onPressed: total == 0 || _deleting ? null : _clearAll,
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('共 $total 筆・本機缺 $missing 筆')),
            ),
            ...?widget.extraActionsBuilder?.call(result),
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
              if (widget.canRetry?.call(result) ?? true) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('重試'),
                  onPressed: _load,
                ),
              ],
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
