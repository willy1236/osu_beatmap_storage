import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../widgets/peer_avatar.dart';

/// 封鎖名單：列出已封鎖的域民，可解除封鎖。進頁時讀取。
class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key, this.service});

  /// 測試用；預設使用 [FriendService.instance]
  final FriendService? service;

  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  final Set<String> _busy = {};

  FriendService get _service => widget.service ?? FriendService.instance;

  @override
  void initState() {
    super.initState();
    // refreshBlocks 會同步 notifyListeners，不能在 build 期間呼叫
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _service.refreshBlocks();
    });
  }

  Future<void> _unblock(FriendPeer p) async {
    setState(() => _busy.add(p.accountId));
    final r = await _service.unblock(p.accountId);
    if (!mounted) return;
    setState(() => _busy.remove(p.accountId));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(r.ok ? '已解除封鎖' : r.message ?? '操作失敗')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final s = _service;
        return Scaffold(
          appBar: AppBar(
            title: const Text('封鎖名單'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重新整理',
                onPressed: s.blocksLoading ? null : s.refreshBlocks,
              ),
            ],
          ),
          body: _body(s),
        );
      },
    );
  }

  Widget _body(FriendService s) {
    if (!s.blocksLoaded) {
      if (s.blocksError != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              SelectableText(s.blocksError!),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
                onPressed: s.refreshBlocks,
              ),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        if (s.blocksError != null)
          MaterialBanner(
            content: Text('${s.blocksError}（顯示的是上次讀到的資料）'),
            actions: [
              TextButton(onPressed: s.refreshBlocks, child: const Text('重試')),
            ],
          ),
        if (s.blocks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('沒有封鎖的域民', style: TextStyle(color: Colors.grey)),
          ),
        for (final p in s.blocks)
          ListTile(
            leading: PeerAvatar(picture: p.picture),
            title: Text(p.displayName),
            trailing: TextButton(
              onPressed: _busy.contains(p.accountId) ? null : () => _unblock(p),
              child: const Text('解除封鎖'),
            ),
          ),
      ],
    );
  }
}
