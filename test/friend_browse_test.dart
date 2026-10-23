import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:osu_beatmap_storage/pages/cloud_list_page.dart';
import 'package:osu_beatmap_storage/pages/friends_page.dart';
import 'package:osu_beatmap_storage/services/cloud_sync_service.dart';
import 'package:osu_beatmap_storage/services/friend_browse_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/osu_settings_service.dart';
import 'package:osu_beatmap_storage/widgets/browse_setting.dart';
import 'package:osu_beatmap_storage/widgets/friend_copy_button.dart';

import 'friend_test_helpers.dart';

http.Response _list() => jsonResp({
  'owner': {'username': '小明', 'account_id': bId},
  'entries': [
    {'online_id': 1, 'title': 'A', 'date_added': '2026-10-01T00:00:00Z'},
  ],
});

void main() {
  late FakeFriendBackend be;
  setUp(() => be = FakeFriendBackend());

  group('FriendBrowseService', () {
    test('fetch 200：解析擁有者與清單，路徑為好友端點', () async {
      be.override = (r) => _list();
      final r = await FriendBrowseService(api: be.api).fetch(bId);
      expect(r.ok, isTrue);
      expect(r.entries.length, 1);
      expect(r.ownerUsername, '小明');
      expect(be.calls.single.url.path, '/osu/friends/$bId/beatmaps');
    });

    test('fetch 403：無法瀏覽，且不提供重試', () async {
      be.override = (r) => jsonResp({'err': 'not_friend'}, 403);
      final r = await FriendBrowseService(api: be.api).fetch(bId);
      expect(r.ok, isFalse);
      expect(r.expired, isTrue);
      expect(r.message, kFriendNotBrowsable);
    });

    test('copy：成功後通知、429 為 rateLimited、403 為無法瀏覽', () async {
      var copied = 0;
      final s = FriendBrowseService(api: be.api, onCopied: () => copied++);
      be.override = (r) => jsonResp({'inserted': 2, 'updated': 3});
      var r = await s.copyToMine(bId);
      expect((r.ok, r.inserted, r.updated, copied), (true, 2, 3, 1));
      expect(be.calls.last.method, 'POST');
      expect(be.calls.last.url.path, '/osu/friends/$bId/copy');

      be.override = (r) => http.Response('', 429);
      r = await s.copyToMine(bId);
      expect(r.status, CloudSyncStatus.rateLimited);
      expect(r.message, '請稍後再試');

      be.override = (r) => jsonResp({'err': 'not_friend'}, 403);
      r = await s.copyToMine(bId);
      expect(r.message, kFriendNotBrowsable);
      expect(copied, 1);
    });
  });

  group('FriendService canBrowse', () {
    Future<FriendService> make() async {
      final auth = makeAuth();
      await auth.init();
      return FriendService(api: be.api, auth: auth);
    }

    test('只有 browsable 名單內的好友 canBrowse 為 true（id 不分大小寫）', () async {
      be.friends = [
        peerJson(bId, '小明', timeKey: 'since'),
        peerJson(cId, '小華', timeKey: 'since'),
      ];
      be.override = (r) => r.url.path == '/osu/friends/browsable'
          ? jsonResp({
              'account_ids': [bId.toUpperCase()],
            })
          : null;
      final s = await make();
      await s.refresh();
      expect(s.friends.map((p) => p.canBrowse), [true, false]);
    });

    test('browsable 讀取失敗：好友列表照常載入，入口不顯示', () async {
      be.friends = [peerJson(bId, '小明', timeKey: 'since')];
      be.override = (r) => r.url.path == '/osu/friends/browsable'
          ? http.Response('', 500)
          : null;
      final s = await make();
      await s.refresh();
      expect(s.loaded, isTrue);
      expect(s.error, isNull);
      expect(s.friends.single.canBrowse, isFalse);
    });
  });

  group('FriendsPage 看清單入口', () {
    testWidgets('只有 canBrowse 的好友顯示，開頁時重讀 browsable', (t) async {
      be.friends = [
        peerJson(bId, '小明', timeKey: 'since'),
        peerJson(cId, '小華', timeKey: 'since'),
      ];
      be.override = (r) {
        if (r.url.path == '/osu/friends/browsable') {
          return jsonResp({
            'account_ids': [bId],
          });
        }
        if (r.url.path == '/osu/friends/$bId/beatmaps') return _list();
        return null;
      };
      final auth = makeAuth();
      await auth.init();
      final s = FriendService(api: be.api, auth: auth);
      await t.pumpWidget(
        MaterialApp(
          home: FriendsPage(service: s, auth: auth),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('看清單'), findsOneWidget);

      expect(
        be.calls.where((c) => c.url.path == '/osu/friends/browsable'),
        isNotEmpty,
      );
    });
  });

  group('CloudListPage 重新整理與 403', () {
    testWidgets('403 顯示無法瀏覽且無重試；重新整理按鈕會重讀', (t) async {
      var denied = true;
      be.override = (r) =>
          denied ? jsonResp({'err': 'not_friend'}, 403) : _list();
      final svc = FriendBrowseService(api: be.api);
      await t.pumpWidget(
        MaterialApp(
          home: CloudListPage(
            title: '好友',
            loader: () => svc.fetch(bId),
            localIds: const {},
            canRetry: (r) => false,
            extraActionsBuilder: (r) => [
              FriendCopyButton(
                accountId: bId,
                count: r.entries.length,
                service: svc,
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(kFriendNotBrowsable), findsOneWidget);
      expect(find.text('重試'), findsNothing);

      denied = false;
      await t.tap(find.byIcon(Icons.refresh));
      await t.pumpAndSettle();
      expect(find.text(kFriendNotBrowsable), findsNothing);
      expect(find.byType(FriendCopyButton), findsOneWidget);
    });
  });

  group('OsuSettingsService 與 BrowseSetting', () {
    test('GET／PUT /osu/settings', () async {
      bool value = true;
      be.override = (r) {
        if (r.method == 'PUT') {
          value = r.body.contains('false') ? false : true;
        }
        return jsonResp({'friends_can_browse': value});
      };
      final s = OsuSettingsService(api: be.api);
      expect(await s.getFriendsCanBrowse(), isTrue);
      expect(await s.setFriendsCanBrowse(false), isFalse);
      expect(be.calls.last.method, 'PUT');
      expect(be.calls.last.url.path, '/osu/settings');
      be.override = (r) => http.Response('', 500);
      expect(await s.getFriendsCanBrowse(), isNull);
    });

    testWidgets('開關預設顯示後端的值，切換後呼叫 PUT；失敗時維持原值', (t) async {
      var value = true;
      var fail = false;
      be.override = (r) {
        if (fail) return http.Response('', 500);
        if (r.method == 'PUT') value = !value;
        return jsonResp({'friends_can_browse': value});
      };
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrowseSetting(service: OsuSettingsService(api: be.api)),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );

      await t.tap(find.byType(SwitchListTile));
      await t.pumpAndSettle();
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );

      fail = true;
      await t.tap(find.byType(SwitchListTile));
      await t.pumpAndSettle();
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(find.text('無法更新設定'), findsOneWidget);
    });
  });
}
