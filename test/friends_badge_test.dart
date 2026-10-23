import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/pages/friends_page.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';
import 'package:osu_beatmap_storage/widgets/count_badge.dart';

import 'friend_test_helpers.dart';

Map<String, dynamic> _push(String id, {required bool read}) => {
  'id': id,
  'from': {'account_id': bId, 'username': '小明', 'picture': null},
  'message': '',
  'entries': <Map<String, dynamic>>[],
  'created_at': '2026-10-02T00:00:00Z',
  'read': read,
};

void main() {
  testWidgets('CountBadge：0 不顯示，超過 99 顯示 99+', (t) async {
    Widget w(int n) => MaterialApp(
      home: CountBadge(count: n, child: const Icon(Icons.people)),
    );
    await t.pumpWidget(w(0));
    expect(find.byType(Text), findsNothing);
    await t.pumpWidget(w(5));
    expect(find.text('5'), findsOneWidget);
    await t.pumpWidget(w(120));
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('好友頁收件匣圖示帶未讀數，標為已讀後消失', (t) async {
    var read = false;
    final be = FakeFriendBackend()
      ..override = (r) => r.method == 'GET' && r.url.path == '/osu/pushes'
          ? jsonResp({
              'pushes': [
                _push('a', read: false),
                _push('b', read: read),
                _push('c', read: true),
              ],
            })
          : null;
    final auth = makeAuth();
    await auth.init();
    final f = FriendService(api: be.api, auth: auth);
    final p = PushService(api: be.api, auth: auth, friends: f);
    await t.runAsync(pumpEventQueue);
    await t.pumpWidget(
      MaterialApp(
        home: FriendsPage(service: f, auth: auth, push: p),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    read = true;
    await t.runAsync(p.refresh);
    await t.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });
}
