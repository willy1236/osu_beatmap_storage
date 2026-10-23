import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 用系統瀏覽器開啟 osu! 官網的圖譜頁；沒有 OnlineID（本機自製圖譜）時不顯示
class OpenWebButton extends StatelessWidget {
  final int onlineID;

  const OpenWebButton({super.key, required this.onlineID});

  @override
  Widget build(BuildContext context) {
    if (onlineID <= 0) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.open_in_new, size: 20),
      tooltip: '開啟圖譜網頁',
      visualDensity: VisualDensity.compact,
      onPressed: () => launchUrl(
        Uri.parse('https://osu.ppy.sh/beatmapsets/$onlineID'),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}
