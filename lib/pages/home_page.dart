import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'beatmap_list_page.dart';
import 'replay_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  static const _pages = [BeatmapListPage(), ReplayListPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
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
            child: IndexedStack(index: _selectedIndex, children: _pages),
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
                AuthStatus.loggedIn => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_circle_outlined),
                    Text(
                      auth.username ?? '',
                      style: textTheme,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    TextButton(
                      onPressed: auth.logout,
                      child: const Text('登出'),
                    ),
                  ],
                ),
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
