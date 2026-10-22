import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'widgets/danser_setup_gate.dart';

/// 全域 navigator，供沒有 BuildContext 的入口（例如 ShareLinkOpener）開啟頁面與對話框
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class OsuBeatmapApp extends StatelessWidget {
  const OsuBeatmapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'osu! Beatmap Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pinkAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const DanserSetupGate(child: HomePage()),
    );
  }
}
