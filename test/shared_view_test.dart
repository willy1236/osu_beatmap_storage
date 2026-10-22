import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/models/cloud_entry.dart';
import 'package:osu_beatmap_storage/pages/cloud_list_page.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/cloud_list_service.dart';
import 'package:osu_beatmap_storage/services/cloud_sync_service.dart';
import 'package:osu_beatmap_storage/services/shared_list_service.dart';
import 'package:osu_beatmap_storage/widgets/shared_copy_button.dart';

void main() {
  CloudEntry e(int id) =>
      CloudEntry(onlineId: id, title: 't$id', dateAdded: DateTime(2026));

  Future<void> pumpPage(
    WidgetTester t,
    Future<CloudListResult> Function() loader, {
    List<Widget> Function(CloudListResult)? extra,
    bool Function(CloudListResult)? canRetry,
  }) async {
    await t.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: CloudListPage(
          title: '雲端清單',
          loader: loader,
          localIds: const {1},
          extraActionsBuilder: extra,
          canRetry: canRetry,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  group('CloudListPage 擴充', () {
    testWidgets('有擁有者代號時標題改為「X」的清單，並顯示額外動作與本機有／缺', (t) async {
      await pumpPage(
        t,
        () async => CloudListResult(
          CloudSyncStatus.success,
          entries: [e(1), e(2)],
          ownerUsername: '小明',
        ),
        extra: (r) => [Text('extra ${r.entries.length}')],
      );
      expect(find.text('「小明」的清單'), findsOneWidget);
      expect(find.text('extra 2'), findsOneWidget);
      expect(find.text('本機有'), findsOneWidget);
      expect(find.text('本機缺'), findsWidgets);
    });

    testWidgets('沒有擁有者代號（自己的清單或空字串）維持原標題', (t) async {
      await pumpPage(
        t,
        () async => CloudListResult(
          CloudSyncStatus.success,
          entries: [e(1)],
          ownerUsername: '',
        ),
      );
      expect(find.text('雲端清單'), findsOneWidget);
    });

    testWidgets('canRetry 為 false 時不顯示重試；預設顯示', (t) async {
      Future<CloudListResult> fail() async => const SharedListResult(
        CloudSyncStatus.failed,
        message: kSharedLinkExpired,
        expired: true,
      );
      await pumpPage(t, fail, canRetry: (r) => false);
      expect(find.text('連結已失效'), findsOneWidget);
      expect(find.text('重試'), findsNothing);

      await pumpPage(t, fail);
      expect(find.text('重試'), findsOneWidget);
    });
  });

  group('SharedCopyButton', () {
    SharedListService svc(int code, List<String> calls) => SharedListService(
      api: ApiClient(
        httpClient: MockClient((r) async {
          calls.add('${r.method} ${r.url.path}');
          return http.Response(
            jsonEncode(
              code == 200 ? {'inserted': 3, 'updated': 2} : {'err': 'x'},
            ),
            code,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        tokenProvider: () async => 't',
        refreshToken: (_) async => null,
        onUnauthorized: () async {},
        baseUrl: 'https://api.test',
      ),
    );

    Future<void> pumpButton(
      WidgetTester t,
      SharedListService s, {
      int count = 5,
    }) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedCopyButton(token: 'abc', count: count, service: s),
        ),
      ),
    );

    testWidgets('確認對話框說明筆數與規則；取消不呼叫', (t) async {
      final calls = <String>[];
      await pumpButton(t, svc(200, calls));
      await t.tap(find.byType(IconButton));
      await t.pumpAndSettle();
      expect(find.textContaining('5 筆'), findsOneWidget);
      expect(find.textContaining('加入日期取最早'), findsOneWidget);
      expect(find.textContaining('無法撤銷'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('確認後顯示新增與更新筆數', (t) async {
      final calls = <String>[];
      await pumpButton(t, svc(200, calls));
      await t.tap(find.byType(IconButton));
      await t.pumpAndSettle();
      await t.tap(find.text('複製'));
      await t.pumpAndSettle();
      expect(calls, ['POST /osu/shared/abc/copy']);
      expect(find.text('已複製：新增 3 筆、更新 2 筆'), findsOneWidget);
    });

    testWidgets('429 顯示請稍後再試', (t) async {
      await pumpButton(t, svc(429, []));
      await t.tap(find.byType(IconButton));
      await t.pumpAndSettle();
      await t.tap(find.text('複製'));
      await t.pumpAndSettle();
      expect(find.text('請稍後再試'), findsOneWidget);
    });

    testWidgets('清單為空時按鈕停用', (t) async {
      await pumpButton(t, svc(200, []), count: 0);
      expect(t.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    });
  });
}
