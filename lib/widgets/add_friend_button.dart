import 'package:flutter/material.dart';

import '../services/friend_service.dart';

/// 分享清單頁 AppBar 的「加好友」：對清單擁有者送好友邀請。
///
/// - [ownerAccountId]（後端有提供時）：開頁就依 [FriendService] 的列表顯示「已是好友」
///   「已送出邀請」；對方已邀請我時按下去等於接受（後端互送直接成為好友）
/// - 沒有 [ownerAccountId]：開頁一律顯示「加好友」，按下後依回應顯示結果
class AddFriendButton extends StatefulWidget {
  const AddFriendButton({
    super.key,
    required this.token,
    this.ownerAccountId,
    this.service,
  });

  final String token;
  final String? ownerAccountId;

  /// 測試用；預設使用 [FriendService.instance]
  final FriendService? service;

  @override
  State<AddFriendButton> createState() => _AddFriendButtonState();
}

enum _Outcome { none, sent, friends }

class _AddFriendButtonState extends State<AddFriendButton> {
  bool _busy = false;
  _Outcome _outcome = _Outcome.none;

  FriendService get _service => widget.service ?? FriendService.instance;

  Future<void> _send() async {
    setState(() => _busy = true);
    final r = await _service.sendViaShare(widget.token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.status == FriendActionStatus.sent) _outcome = _Outcome.sent;
      if (r.status == FriendActionStatus.friends) _outcome = _Outcome.friends;
      // 後端回已是好友：之後按鈕也維持「已是好友」
      if (r.code == 'already_friends') _outcome = _Outcome.friends;
    });
    final text = switch (r.status) {
      FriendActionStatus.sent => '已送出好友邀請',
      FriendActionStatus.friends => '你們已成為好友',
      _ => r.message ?? '操作失敗',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final id = widget.ownerAccountId;
        final relation = id == null
            ? FriendRelation.none
            : _service.relationOf(id);
        final (label, icon, enabled) = switch ((relation, _outcome)) {
          (FriendRelation.self, _) => ('這是你自己', Icons.person, false),
          (FriendRelation.friends, _) ||
          (_, _Outcome.friends) => ('已是好友', Icons.how_to_reg, false),
          (FriendRelation.outgoing, _) ||
          (_, _Outcome.sent) => ('已送出邀請', Icons.hourglass_top, false),
          _ => ('加好友', Icons.person_add, !_busy),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon),
            label: Text(label),
            onPressed: enabled ? _send : null,
          ),
        );
      },
    );
  }
}
