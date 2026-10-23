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

CloudEntry e(int id, String title, {String artist = '', String creator = ''}) =>
    CloudEntry(
      onlineId: id,
      title: title,
      artist: artist,
      creator: creator,
      dateAdded: DateTime.utc(2024),
    );

CloudListService make(
  Future<http.Response> Function(http.Request) h, {
  Future<String?> Function()? token,
  void Function()? onChanged,
}) => CloudListService(
  onChanged: onChanged ?? () {},
  api: ApiClient(
    httpClient: MockClient(h),
    tokenProvider: token ?? () async => 'tok',
    refreshToken: (_) async => null,
    onUnauthorized: () async {},
    baseUrl: 'https://api.test',
  ),
);

void main() {
  group('CloudListService.fetchMine', () {
    test('200 解析 entries 並送 GET /osu/beatmaps', () async {
      late http.Request req;
      final s = make((r) async {
        req = r;
        return http.Response(
          jsonEncode({
            'entries': [e(2, 'b').toJson(), e(1, '標題').toJson()],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final r = await s.fetchMine();
      expect(r.ok, isTrue);
      expect(r.entries.map((x) => x.onlineId), [2, 1]);
      expect(r.entries[1].title, '標題');
      expect(req.method, 'GET');
      expect(req.url.path, '/osu/beatmaps');
    });

    test('空清單', () async {
      final r = await make(
        (_) async => http.Response('{"entries":[]}', 200),
      ).fetchMine();
      expect(r.ok, isTrue);
      expect(r.entries, isEmpty);
    });

    test('錯誤碼對應', () async {
      Future<CloudSyncStatus> st(int c) async =>
          (await make((_) async => http.Response('{}', c)).fetchMine()).status;
      expect(await st(401), CloudSyncStatus.unauthorized);
      expect(await st(429), CloudSyncStatus.rateLimited);
      expect(await st(503), CloudSyncStatus.unavailable);
      expect(await st(500), CloudSyncStatus.failed);
    });

    test('未登入、網路錯誤、格式錯誤', () async {
      final a = await make(
        (_) async => http.Response('', 200),
        token: () async => null,
      ).fetchMine();
      expect(a.status, CloudSyncStatus.unauthorized);
      final b = await make(
        (_) async => throw http.ClientException('down'),
      ).fetchMine();
      expect(b.status, CloudSyncStatus.failed);
      final c = await make(
        (_) async => http.Response('not json', 200),
      ).fetchMine();
      expect(c.status, CloudSyncStatus.failed);
    });
  });

  group('filterCloudEntries', () {
    final list = [
      e(1, 'Alpha', artist: 'Foo'),
      e(2, 'Beta', creator: 'Mapper'),
      e(3, 'Gamma'),
    ];
    test('搜尋標題、藝術家、製圖者（不分大小寫）', () {
      expect(filterCloudEntries(list, query: 'alp').map((x) => x.onlineId), [
        1,
      ]);
      expect(filterCloudEntries(list, query: 'FOO').map((x) => x.onlineId), [
        1,
      ]);
      expect(filterCloudEntries(list, query: 'mapper').map((x) => x.onlineId), [
        2,
      ]);
    });
    test('只看本機缺', () {
      expect(
        filterCloudEntries(
          list,
          onlyMissing: true,
          localIds: {1, 3},
        ).map((x) => x.onlineId),
        [2],
      );
      expect(filterCloudEntries(list, onlyMissing: true).length, 3);
    });
  });

  test('toCsvRow 格式與 CSV 匯出一致', () {
    final row = CloudEntry(
      onlineId: 5,
      title: 'T',
      status: 1,
      difficultyCount: 3,
      modes: ['osu', 'taiko'],
      minStar: 1.234,
      maxStar: 5,
      minBpm: 120.2,
      maxBpm: 180.4,
      dateAdded: DateTime(2024, 3, 5, 12),
    ).toCsvRow();
    expect(row['OnlineID'], '5');
    expect(row['Status'], 'Ranked');
    expect(row['模式'], 'osu/taiko');
    expect(row['最低星數'], '1.23');
    expect(row['最高星數'], '5.00');
    expect(row['BPM'], '120-180');
    expect(row['加入日期'], '2024-03-05');
    expect(row['提交日期'], '');
  });

  group('CloudListPage', () {
    Widget host(Future<CloudListResult> Function() loader, Set<int> local) =>
        MaterialApp(
          home: CloudListPage(title: '雲端清單', loader: loader, localIds: local),
        );
    CloudListResult okResult(List<CloudEntry> l) =>
        CloudListResult(CloudSyncStatus.success, entries: l);

    testWidgets('本機有／缺標示；本機 0 張全缺', (t) async {
      final list = [e(1, 'Alpha'), e(2, 'Beta')];
      await t.pumpWidget(host(() async => okResult(list), {1}));
      await t.pumpAndSettle();
      expect(find.text('本機有'), findsOneWidget);
      expect(find.text('本機缺'), findsOneWidget);

      await t.pumpWidget(host(() async => okResult(list), {}));
      await t.pumpAndSettle();
      expect(find.text('本機缺'), findsNWidgets(2));
    });

    testWidgets('錯誤顯示訊息，重試後載入成功', (t) async {
      var n = 0;
      await t.pumpWidget(
        host(() async {
          n++;
          return n == 1
              ? const CloudListResult(CloudSyncStatus.failed, message: '讀取失敗：x')
              : okResult([e(1, 'Alpha')]);
        }, {}),
      );
      await t.pumpAndSettle();
      expect(find.text('讀取失敗：x'), findsOneWidget);
      await t.tap(find.text('重試'));
      await t.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('只看本機缺', (t) async {
      await t.pumpWidget(
        host(() async => okResult([e(1, 'Alpha'), e(2, 'Beta')]), {1}),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('只看本機缺'));
      await t.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });
  });
}
