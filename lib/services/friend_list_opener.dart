import 'package:flutter/material.dart';

import '../pages/cloud_list_page.dart';
import '../widgets/friend_copy_button.dart';
import 'friend_browse_service.dart';
import 'friend_service.dart';
import 'local_library_service.dart';
import 'shared_list_service.dart';

/// 從好友列表開啟好友的唯讀雲端清單（寫法照 `ShareLinkOpener`）。
/// 本機清單尚未載入時，圖譜會全部標成「本機缺」。
class FriendListOpener {
  const FriendListOpener._();

  static void open(
    BuildContext context,
    FriendPeer friend, {
    FriendBrowseService? service,
    Set<int>? localIds,
  }) {
    final svc = service ?? FriendBrowseService.instance;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CloudListPage(
          title: '${friend.displayName} 的清單',
          loader: () => svc.fetch(friend.accountId),
          localIds:
              localIds ?? LocalLibraryService.instance.onlineIds ?? const {},
          extraActionsBuilder: (r) => [
            FriendCopyButton(
              accountId: friend.accountId,
              count: r.entries.length,
              service: svc,
            ),
          ],
          canRetry: (r) => !(r is SharedListResult && r.expired),
        ),
      ),
    );
  }
}
