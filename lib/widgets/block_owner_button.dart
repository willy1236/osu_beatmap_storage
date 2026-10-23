import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import 'peer_action_menu.dart';

/// 分享清單頁 AppBar 的「封鎖」：封鎖清單擁有者（確認後才送出）。
///
/// 不顯示已封鎖狀態，封鎖後只以 SnackBar 告知；對自己的清單或沒有
/// [ownerAccountId] 時不顯示。
class BlockOwnerButton extends StatefulWidget {
  const BlockOwnerButton({
    super.key,
    required this.ownerAccountId,
    this.ownerName,
    this.service,
  });

  final String? ownerAccountId;
  final String? ownerName;

  /// 測試用；預設使用 [FriendService.instance]
  final FriendService? service;

  @override
  State<BlockOwnerButton> createState() => _BlockOwnerButtonState();
}

class _BlockOwnerButtonState extends State<BlockOwnerButton> {
  bool _busy = false;

  FriendService get _service => widget.service ?? FriendService.instance;

  Future<void> _block(String id) async {
    final name = (widget.ownerName ?? '').isEmpty ? '這位域民' : widget.ownerName!;
    if (!await confirmDestructive(
      context,
      title: '封鎖',
      content: '要封鎖「$name」嗎？好友關係與雙方之間的邀請會移除，對方不會收到通知，也仍能用分享連結看你的清單。',
      confirmLabel: '封鎖',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final r = await _service.block(id);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(r.ok ? '已封鎖' : r.message ?? '操作失敗')));
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.ownerAccountId;
    if (id == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        if (_service.relationOf(id) == FriendRelation.self) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextButton.icon(
            icon: const Icon(Icons.block),
            label: const Text('封鎖'),
            onPressed: _busy ? null : () => _block(id),
          ),
        );
      },
    );
  }
}
