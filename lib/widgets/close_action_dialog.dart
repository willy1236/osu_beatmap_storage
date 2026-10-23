import 'package:flutter/material.dart';
import '../services/tray_service.dart';

/// 第一次關閉視窗時詢問：縮到系統匣或結束程式，可勾選「記住我的選擇」。
/// 按叉、取消、點對話框外都回 null，代表不關閉。
Future<CloseChoice?> showCloseActionDialog(BuildContext context) {
  return showDialog<CloseChoice>(
    context: context,
    builder: (_) => const _CloseActionDialog(),
  );
}

class _CloseActionDialog extends StatefulWidget {
  const _CloseActionDialog();

  @override
  State<_CloseActionDialog> createState() => _CloseActionDialogState();
}

class _CloseActionDialogState extends State<_CloseActionDialog> {
  bool _remember = false;

  void _choose(CloseAction action) =>
      Navigator.pop(context, (action: action, remember: _remember));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('關閉視窗'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('要縮到系統匣繼續在背景執行，還是結束程式？'),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('記住我的選擇'),
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => _choose(CloseAction.exit),
          child: const Text('結束程式'),
        ),
        FilledButton(
          onPressed: () => _choose(CloseAction.tray),
          child: const Text('縮到系統匣'),
        ),
      ],
    );
  }
}
