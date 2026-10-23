import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/auto_upload_service.dart';
import '../widgets/danser_setup_gate.dart';
import '../widgets/open_share_link_dialog.dart';
import '../widgets/share_dialog.dart';
import 'beatmap_list_page.dart';
import 'replay_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  /// 第一次切到「回放匯出」後才建立該頁，danser 的檢查與下載延後到那時
  bool _replayOpened = false;

  void _select(int i) => setState(() {
    _selectedIndex = i;
    if (i == 1) _replayOpened = true;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            trailing: const Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: _AccountTile(),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: Text('圖譜查看'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle),
                label: Text('回放匯出'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                const BeatmapListPage(),
                if (_replayOpened)
                  const DanserSetupGate(child: ReplayListPage())
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// NavigationRail 底部的帳號入口：登入、取消、登出與狀態提示
class _AccountTile extends StatelessWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
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
                AuthStatus.loggedIn => const _AccountMenuButton(),
                _ => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.login),
                    TextButton(onPressed: auth.login, child: const Text('登入')),
                  ],
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
  const _AccountMenuItem(
    this.icon,
    this.label,
    this.onSelected, {
    this.checked,
  });
  final IconData icon;
  final String label;
  final void Function(BuildContext context) onSelected;

  /// 非 null 時這是勾選型項目：選單開啟時呼叫它取得目前是否勾選，
  /// 點擊後仍呼叫 [onSelected]（由它自行切換狀態）
  final bool Function()? checked;
}

/// 已登入時的帳號區：點擊彈出選單，rail 上只顯示圖示與域民代號。
///
/// 新增選單項目（例如 T-05 的「自動上傳」、T-08 的「開啟分享連結」）：
/// 在 [_items] 清單中加一個 [_AccountMenuItem]；登出固定在清單最後，
/// 新項目請插在標示「新項目插入處」的位置。
class _AccountMenuButton extends StatelessWidget {
  const _AccountMenuButton();

  static final _items = <_AccountMenuItem>[
    _AccountMenuItem(
      Icons.share_outlined,
      '分享我的清單',
      (context) => showShareDialog(context),
    ),
    _AccountMenuItem(
      Icons.cloud_upload_outlined,
      '自動上傳',
      (_) => AutoUploadService.instance.toggle(),
      checked: () => AutoUploadService.instance.enabled,
    ),
    _AccountMenuItem(
      Icons.link,
      '開啟分享連結',
      (context) => showOpenShareLinkDialog(context),
    ),
    // —— 新項目插入處（登出之前）——
  ];

  static final _logout = _AccountMenuItem(
    Icons.logout,
    '登出',
    (_) => AuthService.instance.logout(),
  );

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final textTheme = Theme.of(context).textTheme.bodySmall;
    final all = [..._items, _logout];
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
          if (identical(item, _logout) && _items.isNotEmpty)
            const PopupMenuDivider(),
          if (item.checked case final isChecked?)
            CheckedPopupMenuItem(
              value: item,
              checked: isChecked(),
              child: Text(item.label),
            )
          else
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_circle_outlined),
          Text(
            auth.username ?? '',
            style: textTheme,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
