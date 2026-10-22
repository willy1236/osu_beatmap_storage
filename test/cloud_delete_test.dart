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

CloudEntry e(int id, String title) =>
    CloudEntry(onlineId: id, title: title, dateAdded: DateTime.utc(2024));

CloudListService make(
  Future<http.Response> Function(http.Request) h, {
  Future<String?> Function()? token,
}) => CloudListService(
  api: ApiClient(
    httpClient: MockClient(h),
    tokenProvider: token ?? () async => 'tok',
    refreshToken: (_) async => null,
    onUnauthorized: () async {},
    baseUrl: 'https://api.test',
  ),
);

void main() {
  group('CloudListService 刪除', () {
    test('deleteSome 送 POST /osu/beatmaps/delete 與 online_ids', () async {
      late http.Request req;
      final r = await make((q) async {
        req = q;
        return http.Response('{"deleted":2}', 200);
      }).deleteSome([1, 2, 3]);
      expect(r.ok, isTrue);
      expect(r.deleted, 2);
      expect(req.method, 'POST');
      expect(req.url.path, '/osu/beatmaps/delete');
      expect(jsonDecode(req.body), {
        'online_ids': [1, 2, 3],
      });
    });

    test('clearAll 送 DELETE /osu/beatmaps', () async {
      late http.Request req;
      final r = await make((q) async {
        req = q;
        return http.Response('{"deleted":5}', 200);
      }).clearAll();
      expect(r.ok, isTrue);
      expect(r.deleted, 5);
      expect(req.method, 'DELETE');
      expect(req.url.path, '/osu/beatmaps');
    });

    test('錯誤碼、未登入、網路錯誤、格式錯誤', () async {
      Future<CloudSyncStatus> st(int c) async =>
          (await make((_) async => http.Response('{}', c)).clearAll()).status;
      expect(await st(401), CloudSyncStatus.unauthorized);
      expect(await st(503), CloudSyncStatus.unavailable);
      expect(await st(500), CloudSyncStatus.failed);
      final a = await make(
        (_) async => http.Response('', 200),
        token: () async => null,
      ).deleteSome([1]);
      expect(a.status, CloudSyncStatus.unauthorized);
      final b = await make(
        (_) async => throw http.ClientException('down'),
      ).deleteSome([1]);
      expect(b.status, CloudSyncStatus.failed);
      final c = await make(
        (_) async => http.Response('x', 200),
      ).deleteSome([1]);
      expect(c.status, CloudSyncStatus.failed);
    });
  });

  group('CloudListPage 刪除', () {
    late List<List<int>> deleted;
    var cleared = 0;
    CloudDeleteResult okDelete(int n) =>
        CloudDeleteResult(CloudSyncStatus.success, deleted: n);

    Widget host({bool canDelete = true, bool fail = false}) {
      deleted = [];
      cleared = 0;
      return MaterialApp(
        home: CloudListPage(
          title: '雲端清單',
          localIds: const {},
          canDelete: canDelete,
          loader: () async => CloudListResult(
            CloudSyncStatus.success,
            entries: [e(1, 'Alpha'), e(2, 'Beta'), e(3, 'Gamma')],
          ),
          onDelete: (ids) async {
            deleted.add(ids);
            return fail
                ? const CloudDeleteResult(
                    CloudSyncStatus.failed,
                    message: '刪除失敗（HTTP 500）',
                  )
                : okDelete(ids.length);
          },
          onClear: () async {
            cleared++;
            return okDelete(3);
          },
        ),
      );
    }

    Future<void> checkRow(WidgetTester t, int index) async {
      await t.tap(find.byType(Checkbox).at(index));
      await t.pump();
    }

    testWidgets('canDelete 為 false 時沒有刪除與清空按鈕', (t) async {
      await t.pumpWidget(host(canDelete: false));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.delete_sweep), findsNothing);
    });

    testWidgets('勾選多張後刪除：確認後列表少了這些，且對話框有提示', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      await checkRow(t, 0);
      await checkRow(t, 2);
      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      expect(find.textContaining(kCloudDeleteHint), findsOneWidget);
      expect(find.textContaining('2 個圖譜集'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '刪除'));
      await t.pumpAndSettle();
      expect(deleted, [
        [1, 3],
      ]);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Gamma'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('取消刪除：不呼叫、列表不變', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      await checkRow(t, 0);
      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(deleted, isEmpty);
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('刪除失敗：列表維持並顯示訊息', (t) async {
      await t.pumpWidget(host(fail: true));
      await t.pumpAndSettle();
      await checkRow(t, 0);
      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '刪除'));
      await t.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('刪除失敗（HTTP 500）'), findsOneWidget);
    });

    testWidgets('清空需兩層確認，確認後清單為空', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.delete_sweep));
      await t.pumpAndSettle();
      expect(find.textContaining(kCloudDeleteHint), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '繼續'));
      await t.pumpAndSettle();
      expect(cleared, 0);
      expect(find.text('再次確認'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '清空'));
      await t.pumpAndSettle();
      expect(cleared, 1);
      expect(find.text('雲端清單是空的'), findsOneWidget);
    });

    testWidgets('清空在第二層取消：不呼叫', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.delete_sweep));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '繼續'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(cleared, 0);
      expect(find.text('Alpha'), findsOneWidget);
    });
  });
}
