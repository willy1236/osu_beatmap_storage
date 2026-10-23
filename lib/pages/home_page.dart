import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/friend_service.dart';
import '../services/notification_service.dart';
import '../widgets/danser_setup_gate.dart';
import '../widgets/count_badge.dart';
import '../widgets/open_share_link_dialog.dart';
import '../widgets/peer_avatar.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/share_dialog.dart';
import '../widgets/update_button.dart';
import 'beatmap_list_page.dart';
import 'friends_page.dart';
import 'replay_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.auth,
    this.notifications,
    this.friends,
    this.beatmapPage,
    this.friendsPage,
  });

  /// 以下皆為測試用；預設使用各 Service 的單例與正式頁面
  final AuthService? auth;
  final NotificationService? notifications;
  final FriendService? friends;
  @visibleForTesting
  final Widget? beatmapPage;
  @visibleForTesting
  final Widget? friendsPage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  /// 第一次切到「回放匯出」後才建立該頁，danser 的檢查與下載延後到那時
  bool _replayOpened = false;

  static const _friendsIndex = 2;

  NotificationService get _notifications =>
      widget.notifications ?? NotificationService.instance;
  AuthService get _auth => widget.auth ?? AuthService.instance;
  FriendService get _friends => widget.friends ?? FriendService.instance;

  @override
  void initState() {
    super.initState();
    _notifications.intent.addListener(_onNotificationIntent);
  }

  @override
  void dispose() {
    _notifications.intent.removeListener(_onNotificationIntent);
    super.dispose();
  }

  /// 點了通知：切到好友頁，細節由 [FriendsPage] 處理
  void _onNotificationIntent() {
    if (_notifications.intent.value != null) {
      _select(_friendsIndex);
    }
  }

  /// 好友頁在 [IndexedStack] 裡常駐，不會因為切換而重建；每次切到好友頁（含點通知）就重讀，
  /// 讓「看清單」入口等反映對方最新的設定
  void _select(int i) {
    setState(() {
      _selectedIndex = i;
      if (i == 1) _replayOpened = true;
    });
    if (i == _friendsIndex && _auth.isLoggedIn) _friends.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = _notifications;
    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) => _buildScaffold(notifications.badgeCount),
    );
  }

  Widget _buildScaffold(int badge) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const UpdateButton(),
                      const _SettingsButton(),
                      _AccountTile(auth: _auth),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: Text('圖譜查看'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle),
                label: Text('回放匯出'),
              ),
              NavigationRailDestination(
                icon: CountBadge(
                  count: badge,
                  child: const Icon(Icons.people_outline),
                ),
                selectedIcon: CountBadge(
                  count: badge,
                  child: const Icon(Icons.people),
                ),
                label: const Text('好友'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                widget.beatmapPage ?? const BeatmapListPage(),
                if (_replayOpened)
                  const DanserSetupGate(child: ReplayListPage())
                else
                  const SizedBox.shrink(),
                widget.friendsPage ?? const FriendsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// NavigationRail 底部的設定入口，開啟設定對話框
class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '設定',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => showSettingsDialog(context),
    );
  }
}

/// NavigationRail 底部的帳號入口：登入、取消、登出與狀態提示
class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final textTheme = Theme.of(context).textTheme.bodySmall;
        final hint = switch (auth.status) {
          AuthStatus.reloginRequired => '需要重新登入',
          _ => auth.lastError,
        };
        return SizedBox(
          width: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    hint,
                    style: textTheme,
                    textAlign: TextAlign.center,
                  ),
                ),
              switch (auth.status) {
                AuthStatus.loggingIn => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 4),
                    Text('等待瀏覽器登入', style: textTheme),
                    TextButton(
                      onPressed: auth.cancelLogin,
                      child: const Text('取消'),
                    ),
                  ],
                ),
                AuthStatus.loggedIn => _AccountMenuButton(auth: auth),
                // 圖示與文字同屬一個按鈕，點圖示也能登入
                _ => TextButton(
                  onPressed: auth.login,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.login), Text('登入')],
                  ),
                ),
              },
            ],
          ),
        );
      },
    );
  }
}

/// 帳號選單的一個可點項目
class _AccountMenuItem {
  const _AccountMenuItem(this.icon, this.label, this.onSelected);
  final IconData icon;
  final String label;
  final void Function(BuildContext context) onSelected;
}

/// 已登入時的帳號區：點擊彈出選單，rail 上只顯示圖示。
///
/// 新增選單項目（例如 T-08 的「開啟分享連結」）：
/// 在 [_items] 清單中加一個 [_AccountMenuItem]；登出固定在清單最後，
/// 新項目請插在標示「新項目插入處」的位置。
class _AccountMenuButton extends StatelessWidget {
  const _AccountMenuButton({required this.auth});

  final AuthService auth;

  static final _items = <_AccountMenuItem>[
    _AccountMenuItem(
      Icons.share_outlined,
      '分享我的清單',
      (context) => showShareDialog(context),
    ),
    _AccountMenuItem(
      Icons.link,
      '開啟連結',
      (context) => showOpenShareLinkDialog(context),
    ),
    // —— 新項目插入處（登出之前）——
  ];

  @override
  Widget build(BuildContext context) {
    final logout = _AccountMenuItem(Icons.logout, '登出', (_) => auth.logout());
    final all = [..._items, logout];
    return PopupMenuButton<_AccountMenuItem>(
      tooltip: '帳號選單',
      position: PopupMenuPosition.over,
      onSelected: (item) => item.onSelected(context),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            auth.username ?? '',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const PopupMenuDivider(),
        for (final item in all) ...[
          if (identical(item, logout) && _items.isNotEmpty)
            const PopupMenuDivider(),
          PopupMenuItem(
            value: item,
            child: Row(
              children: [
                Icon(item.icon, size: 20),
                const SizedBox(width: 12),
                Text(item.label),
              ],
            ),
          ),
        ],
      ],
      // 代號只顯示在選單標題列，rail 上只留圖示
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: PeerAvatar(picture: auth.picture, radius: 14),
      ),
    );
  }
}
