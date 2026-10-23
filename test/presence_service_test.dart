import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/lazer_detector.dart';
import 'package:osu_beatmap_storage/services/presence_service.dart';
import 'package:osu_beatmap_storage/services/realtime_service.dart';
import 'package:osu_beatmap_storage/widgets/friend_search.dart';
import 'package:osu_beatmap_storage/widgets/presence_setting.dart';

import 'friend_test_helpers.dart';

class _Detector implements LazerDetector {
  bool running = false;
  @override
  Future<bool> isRunning() async => running;
}

class _Conn {
  final body = StreamController<List<int>>();
  void push(String s) => body.add(utf8.encode(s));
  Future<void> end() => body.close();
}

void main() {
  late FakeFriendBackend be;
  late _Detector detector;
  late List<_Conn> conns;
  late List<String> puts; // 'playing' / 'idle'
  late List<Map<String, dynamic>> settingsPuts;
  var visibleOnServer = true;

  setUp(() {
    be = FakeFriendBackend();
    detector = _Detector();
    conns = [];
    puts = [];
    settingsPuts = [];
    visibleOnServer = true;
    be.override = (r) {
      if (r.url.path == '/social/presence' && r.method == 'PUT') {
        puts.add(jsonDecode(r.body)['status'] as String);
        return http.Response('', 204);
      }
      if (r.url.path == '/social/settings') {
        if (r.method == 'PUT') {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          settingsPuts.add(b);
          visibleOnServer = b['presence_visible'] as bool;
        }
        return jsonResp({'presence_visible': visibleOnServer});
      }
      return null;
    };
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  Future<
    ({PresenceService p, RealtimeService rt, FriendService f, AuthService a})
  >
  make({bool connect = true}) async {
    final auth = makeAuth();
    await auth.init();
    final rt = RealtimeService(
      auth: auth,
      clientFactory: () => MockClient.streaming((req, _) async {
        final c = _Conn();
        conns.add(c);
        return http.StreamedResponse(c.body.stream, 200);
      }),
      baseUrl: 'https://api.test',
      backoff: (_) => const Duration(milliseconds: 5),
    );
    final f = FriendService(api: be.api, auth: auth);
    final p = PresenceService(
      api: be.api,
      auth: auth,
      realtime: rt,
      friends: f,
      detector: detector,
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(() {
      p.dispose();
      rt.dispose();
    });
    await settle();
    return (p: p, rt: rt, f: f, a: auth);
  }

  test('lazer 在執行：連上 SSE 後回報 playing；狀態沒變不重複回報；停止後回報 idle', () async {
    detector.running = true;
    await make();
    expect(puts, ['playing']);
    await settle();
    expect(puts, ['playing']);
    detector.running = false;
    await settle();
    expect(puts, ['playing', 'idle']);
  });

  test('只開 stable（偵測為 false）：不回報任何東西', () async {
    await make();
    await settle();
    expect(puts, isEmpty);
  });

  test('重連後補送目前狀態：SSE 斷線再連上，同樣的 playing 再送一次', () async {
    detector.running = true;
    await make();
    expect(puts, ['playing']);
    await conns[0].end(); // 後端把斷線視為 idle，重連後要重新回報
    await settle();
    expect(conns.length, greaterThanOrEqualTo(2));
    expect(puts, ['playing', 'playing']);
  });

  test('SSE 還沒連上時不回報（後端會把它當 idle）', () async {
    detector.running = true;
    final auth = makeAuth();
    await auth.init();
    final rt = RealtimeService(
      auth: auth,
      clientFactory: () => MockClient.streaming((req, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final c = _Conn();
        conns.add(c);
        return http.StreamedResponse(c.body.stream, 200);
      }),
      baseUrl: 'https://api.test',
    );
    final p = PresenceService(
      api: be.api,
      auth: auth,
      realtime: rt,
      friends: FriendService(api: be.api, auth: auth),
      detector: detector,
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(() {
      p.dispose();
      rt.dispose();
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(puts, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(puts, ['playing']);
  });

  test('伺服器上的開關是關閉：登入後讀到，不回報 playing', () async {
    visibleOnServer = false;
    detector.running = true;
    final r = await make();
    expect(r.p.visible, isFalse);
    expect(r.p.visibleLoaded, isTrue);
    expect(puts, isNot(contains('playing')));
  });

  test('關閉開關：PUT settings 並回報 idle；之後不再回報；重新打開後補送', () async {
    detector.running = true;
    final r = await make();
    expect(puts, ['playing']);
    expect(await r.p.setVisible(false), isTrue);
    expect(settingsPuts, [
      {'presence_visible': false},
    ]);
    expect(puts, ['playing', 'idle']);
    await settle();
    expect(puts, ['playing', 'idle']);
    expect(await r.p.setVisible(true), isTrue);
    await settle();
    expect(puts, ['playing', 'idle', 'playing']);
  });

  test('設定更新失敗：回傳 false，開關不變', () async {
    final r = await make();
    be.override = (req) =>
        req.url.path == '/social/settings' ? http.Response('', 500) : null;
    expect(await r.p.setVisible(false), isFalse);
    expect(r.p.visible, isTrue);
  });

  test('presence 事件更新好友的遊玩狀態；resync 重新讀取好友', () async {
    be.friends = [peerJson(bId, 'b', timeKey: 'since')];
    final r = await make();
    expect(r.f.friends.single.playing, isFalse);
    conns[0].push(
      'event: presence\ndata: {"account_id":"$bId","playing":true}\n\n',
    );
    await settle();
    expect(r.f.friends.single.playing, isTrue);
    final before = be.calls
        .where((c) => c.url.path == '/social/friends')
        .length;
    await conns[0].end();
    await settle();
    final after = be.calls.where((c) => c.url.path == '/social/friends').length;
    expect(after, before + 1);
  });

  group('sortAndFilterFriends', () {
    FriendPeer peer(String id, String name, {bool playing = false}) =>
        FriendPeer(accountId: id, username: name, playing: playing);

    test('遊玩中優先，其餘依代號（不分大小寫），未知域民最後', () {
      final out = sortAndFilterFriends([
        peer('1', 'bob'),
        peer('2', ''),
        peer('3', 'Zed', playing: true),
        peer('4', 'alice'),
        peer('5', 'Amy', playing: true),
      ], '');
      expect(out.map((p) => p.accountId), ['5', '3', '4', '1', '2']);
    });

    test('搜尋：包含、不分大小寫、去前後空白；排序照舊', () {
      final list = [
        peer('1', 'Bob'),
        peer('2', 'bobby', playing: true),
        peer('3', 'alice'),
      ];
      expect(sortAndFilterFriends(list, ' BOB ').map((p) => p.accountId), [
        '2',
        '1',
      ]);
      expect(sortAndFilterFriends(list, 'zzz'), isEmpty);
    });
  });

  testWidgets('PresenceSetting：顯示目前值，切換時呼叫 setVisible', (tester) async {
    late PresenceService p;
    late AuthService auth;
    await tester.runAsync(() async {
      final m = await make();
      p = m.p;
      auth = m.a;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PresenceSetting(service: p, auth: auth),
        ),
      ),
    );
    final sw = find.byType(Switch);
    expect(tester.widget<Switch>(sw).value, isTrue);
    await tester.tap(sw);
    await tester.runAsync(() => settle());
    await tester.pump();
    expect(settingsPuts, [
      {'presence_visible': false},
    ]);
    expect(tester.widget<Switch>(sw).value, isFalse);
  });
}
