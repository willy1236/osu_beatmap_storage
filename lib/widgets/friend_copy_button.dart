import 'package:flutter/material.dart';

import '../services/cloud_sync_service.dart' show CloudSyncStatus;
import '../services/friend_browse_service.dart';

/// 好友清單頁 AppBar 的「複製到我的雲端清單」：行為同 `SharedCopyButton`，改呼叫好友端點
class FriendCopyButton extends StatefulWidget {
  const FriendCopyButton({
    super.key,
    required this.accountId,
    required this.count,
    this.service,
  });

  final String accountId;
  final int count;

  /// 測試用；預設使用 [FriendBrowseService.instance]
  final FriendBrowseService? service;

  @override
  State<FriendCopyButton> createState() => _FriendCopyButtonState();
}

class _FriendCopyButtonState extends State<FriendCopyButton> {
  bool _busy = false;

  Future<void> _copy() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('複製到我的雲端清單'),
        content: Text(
          '將把好友清單的 ${widget.count} 筆圖譜併進你的雲端清單。\n\n'
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
    final r = await (widget.service ?? FriendBrowseService.instance).copyToMine(
      widget.accountId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
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
