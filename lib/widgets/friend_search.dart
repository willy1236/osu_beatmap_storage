import 'package:flutter/material.dart';

import '../services/friend_service.dart';

/// 好友列表的顯示順序與搜尋：遊玩中優先，其餘依代號（不分大小寫）；
/// [query] 去掉前後空白後非空時，只留代號包含它的好友（不分大小寫）。代號為空的（未知域民）排最後
List<FriendPeer> sortAndFilterFriends(List<FriendPeer> friends, String query) {
  final q = query.trim().toLowerCase();
  final list = [
    for (final p in friends)
      if (q.isEmpty || p.username.toLowerCase().contains(q)) p,
  ];
  int key(FriendPeer p) => p.username.isEmpty ? 1 : 0;
  list.sort((a, b) {
    if (a.playing != b.playing) return a.playing ? -1 : 1;
    if (key(a) != key(b)) return key(a) - key(b);
    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });
  return list;
}

/// 好友列表上方的搜尋框
class FriendSearchField extends StatelessWidget {
  const FriendSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: TextField(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: '用代號搜尋好友',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onChanged: onChanged,
    ),
  );
}
