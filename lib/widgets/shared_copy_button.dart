import 'package:flutter/material.dart';

import '../services/cloud_presence_service.dart';
import '../services/cloud_sync_service.dart' show CloudSyncStatus;
import '../services/shared_list_service.dart';

/// 分享清單頁 AppBar 的「複製到我的雲端清單」：確認後把對方整份清單併進自己的雲端清單
class SharedCopyButton extends StatefulWidget {
  const SharedCopyButton({
    super.key,
    required this.token,
    required this.count,
    this.service,
  });

  final String token;

  /// 對方清單的筆數（顯示在確認對話框）
  final int count;

  /// 測試用；預設使用 [SharedListService.instance]
  final SharedListService? service;

  @override
  State<SharedCopyButton> createState() => _SharedCopyButtonState();
}

class _SharedCopyButtonState extends State<SharedCopyButton> {
  bool _busy = false;

  Future<void> _copy() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('複製到我的雲端清單'),
        content: Text(
          '將把這份清單的 ${widget.count} 筆圖譜併進你的雲端清單。\n\n'
          '合併規則：加入日期取最早，其餘欄位用最新的值，只新增或更新、不會刪除你原有的紀錄。'
          '完成後無法撤銷。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('複製'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await (widget.service ?? SharedListService.instance).copyToMine(
      widget.token,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) CloudPresenceService.instance.refresh();
    final text = switch (r.status) {
      CloudSyncStatus.success => '已複製：新增 ${r.inserted} 筆、更新 ${r.updated} 筆',
      CloudSyncStatus.rateLimited => '請稍後再試',
      _ => r.message ?? '複製失敗',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.library_add_outlined),
      tooltip: '複製到我的雲端清單',
      onPressed: _busy || widget.count == 0 ? null : _copy,
    );
  }
}
