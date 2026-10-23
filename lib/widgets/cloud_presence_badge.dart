import 'package:flutter/material.dart';

import '../services/cloud_presence_service.dart';

/// 圖譜查看頁每列的雲端標示：已登入並讀到雲端清單後，
/// 在雲端的顯示雲朵，沒有 OnlineID 的顯示「本地圖譜」，其餘不顯示
class CloudPresenceBadge extends StatelessWidget {
  const CloudPresenceBadge({super.key, required this.onlineID, this.service});

  final int onlineID;

  /// 測試用；預設使用 [CloudPresenceService.instance]
  final CloudPresenceService? service;

  @override
  Widget build(BuildContext context) {
    final presence = service ?? CloudPresenceService.instance;
    return ListenableBuilder(
      listenable: presence,
      builder: (context, _) {
        if (!presence.loaded) return const SizedBox.shrink();
        if (onlineID <= 0) {
          return Tooltip(
            message: '沒有 OnlineID，不會上傳到雲端',
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '本地圖譜',
                style: TextStyle(color: Colors.grey[400], fontSize: 11),
              ),
            ),
          );
        }
        if (!presence.contains(onlineID)) return const SizedBox.shrink();
        return Tooltip(
          message: '已在雲端',
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.cloud_done_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}
