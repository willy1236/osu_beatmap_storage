import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/cloud_list_service.dart';
import '../services/cloud_sync_service.dart' show CloudSyncStatus;
import '../services/local_library_service.dart';
import '../services/push_service.dart';
import '../widgets/peer_avatar.dart';
import 'cloud_list_page.dart';

/// 收件匣：好友推送給我的圖譜。點開一筆會標為已讀，並用 [CloudListPage] 顯示圖譜
/// （可勾選下載），另有「收進我的清單」「刪除」。
class InboxPage extends StatelessWidget {
  const InboxPage({super.key, this.service, this.auth, this.localIds});

  /// 測試用；預設使用 [PushService.instance]
  final PushService? service;

  /// 測試用；預設使用 [AuthService.instance]
  final AuthService? auth;

  /// 測試用；預設為本機圖譜庫已讀到的 OnlineID（尚未讀到時視為空）
  final Set<int>? localIds;

  PushService get _service => service ?? PushService.instance;
  AuthService get _auth => auth ?? AuthService.instance;

  static String formatTime(DateTime? t) {
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _open(BuildContext context, PushItem item) async {
    _service.markRead(item.id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CloudListPage(
          title: '${item.from.displayName} 的推送',
          loader: () async =>
              CloudListResult(CloudSyncStatus.success, entries: item.entries),
          localIds: localIds ?? LocalLibraryService.instance.onlineIds ?? {},
          extraActionsBuilder: (_) => [
            _CollectButton(service: _service, item: item),
            _DeleteButton(service: _service, item: item),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_auth, _service]),
      builder: (context, _) {
        final s = _service;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.unreadCount > 0 ? '收件匣（${s.unreadCount} 未讀）' : '收件匣'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重新整理',
                onPressed: s.loading ? null : s.refresh,
              ),
            ],
          ),
          body: !_auth.isLoggedIn
              ? const Center(child: Text('登入析域帳號後才能使用收件匣'))
              : _body(context, s),
        );
      },
    );
  }

  Widget _body(BuildContext context, PushService s) {
    if (!s.loaded) {
      if (s.error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              SelectableText(s.error!),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
                onPressed: s.refresh,
              ),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (s.items.isEmpty) {
      return const Center(child: Text('收件匣是空的'));
    }
    return ListView(
      children: [
        if (s.error != null)
          MaterialBanner(
            content: Text('${s.error}（顯示的是上次讀到的資料）'),
            actions: [
              TextButton(onPressed: s.refresh, child: const Text('重試')),
            ],
          ),
        for (final p in s.items)
          ListTile(
            key: ValueKey(p.id),
            leading: PeerAvatar(picture: p.from.picture),
            title: Text(
              p.from.displayName,
              style: TextStyle(
                fontWeight: p.read ? FontWeight.normal : FontWeight.bold,
              ),
            ),
            subtitle: Text(
              [
                if (p.message.isNotEmpty) p.message,
                '${p.entries.length} 個圖譜集・${formatTime(p.createdAt)}',
              ].join('\n'),
            ),
            isThreeLine: p.message.isNotEmpty,
            trailing: p.read
                ? null
                : const Badge(
                    label: Text('未讀'),
                    backgroundColor: Colors.redAccent,
                  ),
            onTap: () => _open(context, p),
          ),
      ],
    );
  }
}

class _CollectButton extends StatefulWidget {
  const _CollectButton({required this.service, required this.item});

  final PushService service;
  final PushItem item;

  @override
  State<_CollectButton> createState() => _CollectButtonState();
}

class _CollectButtonState extends State<_CollectButton> {
  bool _busy = false;

  Future<void> _collect() async {
    setState(() => _busy = true);
    final r = await widget.service.collect(widget.item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            r.ok
                ? '已收進我的清單：新增 ${r.inserted}、更新 ${r.updated}'
                : (r.message ?? '收進清單失敗'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.library_add),
    label: const Text('收進我的清單'),
    onPressed: _busy ? null : _collect,
  );
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.service, required this.item});

  final PushService service;
  final PushItem item;

  Future<void> _delete(BuildContext context) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除推送'),
        content: const Text('只會從你的收件匣移除，不影響對方與其他收件人。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await service.delete(item.id);
    if (done) nav.pop();
    messenger.showSnackBar(SnackBar(content: Text(done ? '已刪除' : '刪除失敗')));
  }

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.delete_outline),
    tooltip: '刪除這筆推送',
    onPressed: () => _delete(context),
  );
}
