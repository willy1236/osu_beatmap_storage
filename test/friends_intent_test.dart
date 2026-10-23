import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osu_beatmap_storage/pages/friends_page.dart';
import 'package:osu_beatmap_storage/pages/inbox_page.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/notification_service.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';

import 'friend_test_helpers.dart';

void main() {
  late ValueNotifier<NotificationTarget?> intent;

  Future<void> pump(WidgetTester t, {int friends = 0}) async {
    final be = FakeFriendBackend()
      ..friends = [
        for (var i = 0; i < friends; i++)
          peerJson(bId, '好友$i', timeKey: 'since'),
      ]
      ..requests = {
        'incoming': [peerJson(cId, '小華')],
        'outgoing': [],
      }
      ..override = (r) => r.method == 'GET' && r.url.path == '/osu/pushes'
          ? jsonResp({'pushes': []})
          : null;
    final auth = makeAuth();
    await auth.init();
    final f = FriendService(api: be.api, auth: auth);
    final p = PushService(api: be.api, auth: auth, friends: f);
    intent = ValueNotifier(null);
    addTearDown(intent.dispose);
    await t.runAsync(pumpEventQueue);
    await t.pumpWidget(
      MaterialApp(
        home: FriendsPage(service: f, auth: auth, push: p, intent: intent),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('inbox intent：開啟收件匣並清掉 intent', (t) async {
    await pump(t);
    intent.value = NotificationTarget.inbox;
    await t.pumpAndSettle();
    expect(find.byType(InboxPage), findsOneWidget);
    expect(intent.value, isNull);
  });

  testWidgets('invites intent：捲到收到的邀請區（好友很多時標題原本在畫面外）', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, friends: 30);
    expect(find.text('收到的邀請（1）'), findsNothing);
    intent.value = NotificationTarget.invites;
    await t.pumpAndSettle();
    expect(find.text('收到的邀請（1）'), findsOneWidget);
    expect(intent.value, isNull);
  });
}
