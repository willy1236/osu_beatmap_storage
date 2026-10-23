import 'package:flutter/material.dart';

/// 二次確認對話框；使用者按下確認鍵回傳 true
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmLabel,
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
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 好友頁列表項目的「⋮」選單：刪除好友（可省略）與封鎖，兩者都先確認。
class PeerActionMenu extends StatelessWidget {
  const PeerActionMenu({
    super.key,
    required this.name,
    this.onRemove,
    required this.onBlock,
    this.enabled = true,
  });

  final String name;

  /// 為 null 時不顯示「刪除好友」（例如收到的邀請）
  final VoidCallback? onRemove;
  final VoidCallback onBlock;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      enabled: enabled,
      onSelected: (v) async {
        if (v == 'remove') {
          if (await confirmDestructive(
            context,
            title: '刪除好友',
            content: '要刪除好友「$name」嗎？雙方的好友列表都會移除，先前的推送仍會保留。',
            confirmLabel: '刪除',
          )) {
            onRemove?.call();
          }
        } else if (v == 'block') {
          if (await confirmDestructive(
            context,
            title: '封鎖',
            content: '要封鎖「$name」嗎？好友關係與雙方之間的邀請會移除，對方不會收到通知。',
            confirmLabel: '封鎖',
          )) {
            onBlock();
          }
        }
      },
      itemBuilder: (_) => [
        if (onRemove != null)
          const PopupMenuItem(value: 'remove', child: Text('刪除好友')),
        const PopupMenuItem(value: 'block', child: Text('封鎖')),
      ],
    );
  }
}
