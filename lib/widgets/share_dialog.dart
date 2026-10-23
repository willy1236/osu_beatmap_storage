import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/share_service.dart';
import '../utils/share_link.dart';

Future<void> showShareDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const ShareDialog());

/// 「分享我的清單」：查看、產生、複製、重新產生、撤銷分享連結
class ShareDialog extends StatefulWidget {
  const ShareDialog({super.key, this.service});

  /// 測試用；預設使用 [ShareService.instance]
  final ShareService? service;

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  late final ShareService _service = widget.service ?? ShareService.instance;
  bool _loading = true;
  String? _token;
  // 是否確定知道目前有沒有連結；讀取失敗時不知道，不能提供「產生連結」以免繞過重新產生的確認
  bool _known = false;
  // 未登入或登入已失效：重試沒有用，只顯示錯誤訊息
  bool _unauthorized = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _run(_service.fetch());
  }

  /// 執行一個操作並更新狀態；失敗時保留原本顯示的連結並顯示錯誤
  Future<void> _run(Future<ShareResult> op, {bool clearOnOk = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    final r = await op;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _unauthorized = r.status == ShareStatus.unauthorized;
      switch (r.status) {
        case ShareStatus.ok:
          _token = clearOnOk ? null : r.token;
          _known = true;
        case ShareStatus.none:
          _token = null;
          _known = true;
        case ShareStatus.unauthorized:
        case ShareStatus.failed:
          _error = r.message;
      }
    });
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _regenerate() async {
    // 已有連結時重新產生會讓舊連結失效，需二次確認
    if (_token != null &&
        !await _confirm('重新產生連結', '舊連結會立刻失效，已拿到舊連結的人將無法開啟。確定要重新產生嗎？')) {
      return;
    }
    await _run(_service.regenerate());
  }

  Future<void> _revoke() async {
    if (!await _confirm('撤銷連結', '撤銷後沒有任何有效連結，已拿到連結的人將無法開啟。確定要撤銷嗎？')) {
      return;
    }
    await _run(_service.revoke(), clearOnOk: true);
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) setState(() => _notice = '已複製到剪貼簿');
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    final link = token == null ? null : buildShareLink(token);
    return AlertDialog(
      title: const Text('分享我的清單'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (link != null) ...[
              const Text('拿到連結的域民可以瀏覽並下載你的圖譜清單。'),
              const SizedBox(height: 12),
              SelectableText(link),
            ] else if (!_known) ...[
              if (!_unauthorized) const Text('無法讀取目前的分享連結，請重試。'),
            ] else
              const Text('目前沒有分享連結。產生後，拿到連結的域民可以瀏覽並下載你的圖譜清單。'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_notice!),
              ),
          ],
        ),
      ),
      actions: [
        if (link != null) ...[
          TextButton(
            onPressed: _loading ? null : _revoke,
            child: const Text('撤銷'),
          ),
          TextButton(
            onPressed: _loading ? null : _regenerate,
            child: const Text('重新產生'),
          ),
          FilledButton(
            onPressed: _loading ? null : () => _copy(link),
            child: const Text('複製'),
          ),
        ] else if (!_known) ...[
          if (!_unauthorized)
            FilledButton(
              onPressed: _loading ? null : () => _run(_service.fetch()),
              child: const Text('重試'),
            ),
        ] else
          FilledButton(
            onPressed: _loading ? null : _regenerate,
            child: const Text('產生連結'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}
