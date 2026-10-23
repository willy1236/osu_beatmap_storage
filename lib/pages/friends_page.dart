import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friend_list_opener.dart';
import '../services/friend_service.dart';
import '../services/push_service.dart';
import '../widgets/peer_action_menu.dart';
import '../widgets/peer_avatar.dart';
import 'blocked_page.dart';
import 'inbox_page.dart';

/// 好友頁：好友列表、收到的邀請（接受、拒絕）、送出的邀請（取消）。
/// 未登入時只提示登入。
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, this.service, this.auth, this.push});

  /// 測試用；預設使用 [FriendService.instance]
  final FriendService? service;

  /// 測試用；預設使用 [AuthService.instance]
  final AuthService? auth;

  /// 測試用；預設使用 [PushService.instance]
  final PushService? push;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  /// 正在處理的對象（accountId），避免連按
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    // 開好友頁時重讀，讓「看清單」入口反映對方最新的公開設定
    if (_auth.isLoggedIn) _service.refresh();
  }

  FriendService get _service => widget.service ?? FriendService.instance;
  AuthService get _auth => widget.auth ?? AuthService.instance;
  PushService get _push => widget.push ?? PushService.instance;

  Future<void> _run(
    FriendPeer p,
    Future<FriendActionResult> Function() action,
    String okText,
  ) async {
    setState(() => _busy.add(p.accountId));
    final r = await action();
    if (!mounted) return;
    setState(() => _busy.remove(p.accountId));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(r.ok ? okText : r.message ?? '操作失敗')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_auth, _service]),
      builder: (context, _) {
        if (!_auth.isLoggedIn) return _buildSignedOut();
        return Scaffold(
          appBar: AppBar(
            title: const Text('好友'),
            actions: [
              IconButton(
                icon: const Icon(Icons.inbox),
                tooltip: '收件匣',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InboxPage(service: _push, auth: _auth),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.block),
                tooltip: '封鎖名單',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlockedPage(service: widget.service),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重新整理',
                onPressed: _service.loading ? null : _service.refresh,
              ),
            ],
          ),
          body: _buildBody(),
        );
      },
    );
  }

  Widget _buildSignedOut() {
    return Scaffold(
      appBar: AppBar(title: const Text('好友')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('登入析域帳號後才能使用好友功能'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _auth.login, child: const Text('登入')),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final s = _service;
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
    return ListView(
      children: [
        if (s.error != null)
          MaterialBanner(
            content: Text('${s.error}（顯示的是上次讀到的資料）'),
            actions: [
              TextButton(onPressed: s.refresh, child: const Text('重試')),
            ],
          ),
        _header('好友（${s.friends.length}）'),
        if (s.friends.isEmpty) const _Empty('還沒有好友。開啟朋友的分享連結後按「加好友」即可送出邀請。'),
        for (final p in s.friends)
          _tile(
            p,
            actions: [
              if (p.canBrowse)
                TextButton(
                  onPressed: () => FriendListOpener.open(context, p),
                  child: const Text('看清單'),
                ),
              _menu(p, removable: true),
            ],
          ),
        _header('收到的邀請（${s.incoming.length}）'),
        if (s.incoming.isEmpty) const _Empty('沒有收到的邀請'),
        for (final p in s.incoming)
          _tile(
            p,
            actions: [
              TextButton(
                onPressed: _busy.contains(p.accountId)
                    ? null
                    : () => _run(p, () => s.reject(p.accountId), '已拒絕'),
                child: const Text('拒絕'),
              ),
              FilledButton(
                onPressed: _busy.contains(p.accountId)
                    ? null
                    : () => _run(p, () => s.accept(p.accountId), '已成為好友'),
                child: const Text('接受'),
              ),
              _menu(p),
            ],
          ),
        _header('送出的邀請（${s.outgoing.length}）'),
        if (s.outgoing.isEmpty) const _Empty('沒有送出的邀請'),
        for (final p in s.outgoing)
          _tile(
            p,
            actions: [
              TextButton(
                onPressed: _busy.contains(p.accountId)
                    ? null
                    : () => _run(p, () => s.cancel(p.accountId), '已取消邀請'),
                child: const Text('取消邀請'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _menu(FriendPeer p, {bool removable = false}) => PeerActionMenu(
    name: p.displayName,
    enabled: !_busy.contains(p.accountId),
    onRemove: removable
        ? () => _run(p, () => _service.removeFriend(p.accountId), '已刪除好友')
        : null,
    onBlock: () => _run(p, () => _service.block(p.accountId), '已封鎖'),
  );

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _tile(FriendPeer p, {List<Widget> actions = const []}) => ListTile(
    leading: PeerAvatar(picture: p.picture),
    title: Text(p.displayName),
    trailing: actions.isEmpty
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: actions),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(text, style: const TextStyle(color: Colors.grey)),
  );
}
