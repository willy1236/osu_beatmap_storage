import 'package:flutter/material.dart';

import '../services/friend_link_opener.dart';
import '../services/share_link_opener.dart';
import '../utils/friend_link.dart';
import '../utils/share_link.dart';

Future<void> showOpenShareLinkDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const OpenShareLinkDialog());

/// 「開啟連結」：貼上 `osu-storage://share/<token>` 後開啟對方的清單，
/// 或貼上 `osu-storage://friend/<token>` 後用好友邀請連結加好友
class OpenShareLinkDialog extends StatefulWidget {
  const OpenShareLinkDialog({super.key, this.opener, this.friendOpener});

  /// 測試用；預設使用 [ShareLinkOpener.instance]
  final Future<bool> Function(String token)? opener;

  /// 測試用；預設使用 [FriendLinkOpener.instance]
  final Future<bool> Function(String token)? friendOpener;

  @override
  State<OpenShareLinkDialog> createState() => _OpenShareLinkDialogState();
}

class _OpenShareLinkDialogState extends State<OpenShareLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final token = parseShareLink(_controller.text);
    final friendToken = token == null
        ? parseFriendLink(_controller.text)
        : null;
    if (token == null && friendToken == null) {
      setState(() => _error = '連結格式不正確，應為 osu-storage://share/… 或 friend/…');
      return;
    }
    Navigator.pop(context);
    if (token != null) {
      (widget.opener ?? ShareLinkOpener.instance.open)(token);
    } else {
      (widget.friendOpener ?? FriendLinkOpener.instance.open)(friendToken!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('開啟連結'),
      content: SizedBox(
        width: 460,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'osu-storage://share/… 或 friend/…',
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('開啟')),
      ],
    );
  }
}
