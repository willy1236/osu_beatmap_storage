import 'package:flutter/material.dart';

import '../services/friend_lookup.dart';
import '../services/friend_service.dart';
import 'peer_avatar.dart';

/// 好友頁的「加好友」對話框：輸入代號 → 查詢 → 顯示對方 → 按確認才送出邀請。
///
/// [service]、[lookup] 為測試用；預設使用 [FriendService.instance] 與正式 API。
Future<void> showAddFriendDialog(
  BuildContext context, {
  FriendService? service,
  FriendLookup? lookup,
}) => showDialog<void>(
  context: context,
  builder: (_) => AddFriendDialog(
    service: service ?? FriendService.instance,
    lookup: lookup ?? FriendLookup(),
  ),
);

class AddFriendDialog extends StatefulWidget {
  const AddFriendDialog({
    super.key,
    required this.service,
    required this.lookup,
  });

  final FriendService service;
  final FriendLookup lookup;

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  FriendPeer? _peer;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _peer = null;
    });
    final r = await widget.lookup.find(name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _peer = r.peer;
      _error = r.error;
    });
  }

  Future<void> _send() async {
    final p = _peer;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    final r = await widget.service.sendToAccount(p.accountId);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = r.message ?? '操作失敗';
      });
      return;
    }
    final text = r.status == FriendActionStatus.friends
        ? '你們已成為好友'
        : '已送出好友邀請';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    Navigator.of(context).pop();
  }

  /// 對 [p] 的提示與能否送出
  (String?, bool) _hint(FriendPeer p) =>
      switch (widget.service.relationOf(p.accountId)) {
        FriendRelation.self => ('不能對自己送邀請', false),
        FriendRelation.friends => ('你們已經是好友', false),
        FriendRelation.outgoing => ('已送出邀請，等待對方回應', false),
        FriendRelation.incoming => ('對方已邀請你，按確認將直接成為好友', true),
        FriendRelation.none => (null, true),
      };

  @override
  Widget build(BuildContext context) {
    final p = _peer;
    final hint = p == null ? null : _hint(p);
    return AlertDialog(
      title: const Text('加好友'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: '域民代號',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: '查詢',
                  onPressed: _busy ? null : _find,
                ),
              ),
              onChanged: (_) {
                if (p != null || _error != null) {
                  setState(() {
                    _peer = null;
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) => _find(),
            ),
            const SizedBox(height: 16),
            if (_busy && p == null)
              const Center(child: CircularProgressIndicator()),
            if (p != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PeerAvatar(picture: p.picture),
                title: Text(p.displayName),
                subtitle: hint!.$1 == null ? null : Text(hint.$1!),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (p == null)
          FilledButton(onPressed: _busy ? null : _find, child: const Text('查詢'))
        else
          FilledButton(
            onPressed: (_busy || !hint!.$2) ? null : _send,
            child: const Text('確認'),
          ),
      ],
    );
  }
}
