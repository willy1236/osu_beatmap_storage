import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'widgets/danser_setup_gate.dart';

class OsuBeatmapApp extends StatelessWidget {
  const OsuBeatmapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
