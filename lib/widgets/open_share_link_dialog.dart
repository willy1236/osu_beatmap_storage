import 'package:flutter/material.dart';

import '../services/share_link_opener.dart';
import '../utils/share_link.dart';

Future<void> showOpenShareLinkDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const OpenShareLinkDialog());

/// 「開啟分享連結」：貼上 `osu-storage://share/<token>` 後開啟對方的清單
class OpenShareLinkDialog extends StatefulWidget {
  const OpenShareLinkDialog({super.key, this.opener});

  /// 測試用；預設使用 [ShareLinkOpener.instance]
  final Future<bool> Function(String token)? opener;

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
    if (token == null) {
      setState(() => _error = '連結格式不正確，應為 osu-storage://share/…');
      return;
    }
    Navigator.pop(context);
    (widget.opener ?? ShareLinkOpener.instance.open)(token);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('開啟分享連結'),
      content: SizedBox(
        width: 460,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'osu-storage://share/…',
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
