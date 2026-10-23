import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/invite_link_service.dart';
import '../utils/friend_link.dart';

/// 好友頁的「邀請連結」區塊：產生並複製一次性連結、列出未使用的連結（含產生時間）與撤銷。
/// 未使用的連結最多 [kMaxInviteLinks] 條。
class InviteLinksSection extends StatefulWidget {
  const InviteLinksSection({super.key, this.service});

  /// 測試用；預設使用 [InviteLinkService.instance]
  final InviteLinkService? service;

  @override
  State<InviteLinksSection> createState() => _InviteLinksSectionState();
}

class _InviteLinksSectionState extends State<InviteLinksSection> {
  bool _busy = false;

  InviteLinkService get _service =>
      widget.service ?? InviteLinkService.instance;

  @override
  void initState() {
    super.initState();
    _service.refresh();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _create() async {
    setState(() => _busy = true);
    final r = await _service.create();
    if (r.ok) await _copy(r.token!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _toast('已複製邀請連結');
    } else {
      _toast(r.message ?? '操作失敗');
    }
  }

  Future<void> _copy(String token) =>
      Clipboard.setData(ClipboardData(text: buildFriendLink(token)));

  Future<void> _revoke(String token) async {
    setState(() => _busy = true);
    final r = await _service.revoke(token);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(r.ok ? '已撤銷邀請連結' : r.message ?? '操作失敗');
  }

  static String _fmt(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final links = _service.links;
        final full = links.length >= kMaxInviteLinks;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                '邀請連結（${links.length}/$kMaxInviteLinks）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.link),
                    label: const Text('產生並複製連結'),
                    onPressed: _busy || full ? null : _create,
                  ),
                  Text(
                    full
                        ? '已達上限 $kMaxInviteLinks 條，請先撤銷不用的'
                        : '每條連結只能使用一次，用過就失效',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (_service.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _service.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_service.loaded && links.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('沒有未使用的邀請連結', style: TextStyle(color: Colors.grey)),
              ),
            for (final l in links)
              ListTile(
                key: ValueKey('invite-${l.token}'),
                leading: const Icon(Icons.link),
                title: Text('產生於 ${_fmt(l.createdAt)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: '複製連結',
                      onPressed: () async {
                        await _copy(l.token);
                        if (mounted) _toast('已複製邀請連結');
                      },
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _revoke(l.token),
                      child: const Text('撤銷'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
