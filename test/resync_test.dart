import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/friend_service.dart';
import 'package:osu_beatmap_storage/services/notification_service.dart';
import 'package:osu_beatmap_storage/services/presence_service.dart';
import 'package:osu_beatmap_storage/services/lazer_detector.dart';
import 'package:osu_beatmap_storage/services/push_service.dart';
import 'package:osu_beatmap_storage/services/realtime_service.dart';
import 'package:osu_beatmap_storage/services/toast_platform.dart';

import 'friend_test_helpers.dart';

class _Conn {
  final body = StreamController<List<int>>();
  Future<void> end() => body.close();
}

class _Toast implements ToastPlatform {
  int shown = 0;
  @override
  Future<void> show({
    required String title,
    required String body,
    required VoidCallback onClick,
  }) async => shown++;
}

class _Idle implements LazerDetector {
  @override
  Future<bool> isRunning() async => false;
}

/// T-12 / T-09：重連（resyncRequested）時，好友列表與收件匣各自整份重讀一次，
/// 紅點更新、不發 toast
void main() {
  test('重連：FriendService、PushService 各重讀一次，紅點更新，不發 toast', () async {
    final be = FakeFriendBackend();
    var pushes = <dynamic>[];
    be.override = (r) {
      if (r.url.path == '/osu/pushes' && r.method == 'GET') {
        return jsonResp({'pushes': pushes});
      }
      if (r.url.path == '/social/settings') {
        return jsonResp({'presence_visible': true});
      }
      return null;
    };
    final auth = makeAuth();
    await auth.init();
    final conns = <_Conn>[];
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
    final f = FriendService(api: be.api, auth: auth, realtime: rt);
    final p = PushService(
      api: be.api,
      auth: auth,
      friends: f,
      realtime: rt,
      onCollected: () {},
    );
    final toast = _Toast();
    final n = NotificationService(
      auth: auth,
      realtime: rt,
      friends: f,
      push: p,
      toast: toast,
      restoreWindow: () async {},
    );
    // PresenceService 不再自己重讀好友列表，不能造成重複請求
    final presence = PresenceService(
      api: be.api,
      auth: auth,
      realtime: rt,
      friends: f,
      detector: _Idle(),
      interval: const Duration(seconds: 30),
    );
    addTearDown(() {
      presence.dispose();
      n.dispose();
      p.dispose();
      f.dispose();
      rt.dispose();
    });
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 80));
    int count(String path) =>
        be.calls.where((c) => c.method == 'GET' && c.url.path == path).length;

    await settle();
    expect(conns, hasLength(1));
    expect(n.badgeCount, 0);
    final friendsBefore = count('/social/friends');
    final requestsBefore = count('/social/requests');
    final pushesBefore = count('/osu/pushes');

    // 斷線期間錯過的邀請與推送
    be.requests = {
      'incoming': [peerJson(bId, '小明')],
      'outgoing': [],
    };
    pushes = [
      {
        'id': 'p1',
        'from': {'account_id': bId, 'username': '小明', 'picture': null},
        'message': '嗨',
        'entries': [
          {'online_id': 1, 'title': 't', 'date_added': '2026-10-01T00:00:00Z'},
        ],
        'created_at': '2026-10-02T00:00:00Z',
        'read': false,
      },
    ];
    await conns[0].end();
    await settle();

    expect(conns, hasLength(2));
    expect(f.incoming, hasLength(1));
    expect(p.unreadCount, 1);
    expect(n.badgeCount, 2);
    expect(toast.shown, 0);
    expect(count('/social/friends'), friendsBefore + 1);
    expect(count('/social/requests'), requestsBefore + 1);
    expect(count('/osu/pushes'), pushesBefore + 1);
  });
}
