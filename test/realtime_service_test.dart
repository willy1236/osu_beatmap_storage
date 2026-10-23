import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';
import 'package:osu_beatmap_storage/services/realtime_service.dart';

class _Store implements AuthTokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

class _Prefs implements AuthPrefs {
  ({String sub, String username})? account;
  @override
  Future<({String sub, String username})?> getAccount() async => account;
  @override
  Future<void> setAccount(String? sub, String? username) async =>
      account = sub == null ? null : (sub: sub, username: username ?? '');
  @override
  Future<bool> getForceLogin() async => false;
  @override
  Future<void> setForceLogin(bool value) async {}
}

/// 一次連線：記下請求，由測試用 [push]、[end] 控制串流
class _Conn {
  _Conn(this.request, this.status);
  final http.BaseRequest request;
  final int status;
  final body = StreamController<List<int>>();
  void push(String s) => body.add(utf8.encode(s));
  Future<void> end() => body.close();
  String? get token => request.headers['Authorization'];
}

void main() {
  late _Store store;
  late _Prefs prefs;
  late List<_Conn> conns;
  late List<int> statuses; // 依序決定每次連線的狀態碼，用完回 200

  setUp(() {
    store = _Store();
    prefs = _Prefs();
    conns = [];
    statuses = [];
  });

  AuthService makeAuth() => AuthService(
    tokenStore: store,
    prefs: prefs,
    httpClient: MockClient((_) async => http.Response('', 200)),
  );

  Future<AuthService> loggedIn([String sub = 'A']) async {
    prefs.account = (sub: sub, username: 'u');
    store.value = jsonEncode({
      'access': 'tok-$sub',
      'refresh': 'r',
      'expires_at': DateTime(2099).millisecondsSinceEpoch,
    });
    final auth = makeAuth();
    await auth.init();
    return auth;
  }

  http.Client factory() => MockClient.streaming((req, _) async {
    final c = _Conn(req, statuses.isEmpty ? 200 : statuses.removeAt(0));
    conns.add(c);
    return http.StreamedResponse(c.body.stream, c.status);
  });

  RealtimeService make(AuthService auth, {Duration? idle}) => RealtimeService(
    auth: auth,
    clientFactory: factory,
    baseUrl: 'https://api.test',
    idleTimeout: idle,
    backoff: (_) => const Duration(milliseconds: 5),
  );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  test('未登入：不連線', () async {
    final r = make(makeAuth());
    await settle();
    expect(conns, isEmpty);
    r.dispose();
  });

  test('登入後連線，帶 Bearer token 與 SSE header', () async {
    final r = make(await loggedIn());
    await settle();
    expect(conns, hasLength(1));
    expect(conns[0].request.url.toString(), 'https://api.test/social/events');
    expect(conns[0].token, 'Bearer tok-A');
    expect(conns[0].request.headers['Accept'], 'text/event-stream');
    r.dispose();
  });

  test('事件依型別分派；忽略註解行、壞 JSON、未訂閱型別；可取消訂閱', () async {
    final r = make(await loggedIn());
    final got = <Map<String, dynamic>>[];
    final cancel = r.on('push', got.add);
    r.on('push', (_) => throw StateError('handler 壞掉不能影響別人'));
    await settle();
    conns[0].push(': connected\n\n');
    conns[0].push('event: push\ndata: {"id":"1",');
    conns[0].push('"message":"嗨"}\n\n');
    conns[0].push(': ping\n\nevent: push\ndata: not json\n\n');
    conns[0].push('event: other\ndata: {"x":1}\n\n');
    await settle();
    expect(got, [
      {'id': '1', 'message': '嗨'},
    ]);
    cancel();
    conns[0].push('event: push\ndata: {"id":"2"}\n\n');
    await settle();
    expect(got, hasLength(1));
    r.dispose();
  });

  test('串流結束後重連並發出 resync；第一次連線不發', () async {
    final r = make(await loggedIn());
    var resyncs = 0;
    r.resyncRequested.addListener(() => resyncs++);
    await settle();
    expect(conns, hasLength(1));
    expect(resyncs, 0);
    await conns[0].end();
    await settle();
    expect(conns, hasLength(2));
    expect(resyncs, 1);
    r.dispose();
  });

  test('連線失敗（5xx）退避重試，成功後才發 resync 且前一次失敗不發', () async {
    statuses = [200, 503, 200];
    final r = make(await loggedIn());
    var resyncs = 0;
    r.resyncRequested.addListener(() => resyncs++);
    await settle();
    await conns[0].end();
    await settle();
    expect(conns.length, 3);
    expect(resyncs, 1);
    r.dispose();
  });

  test('401：refresh 後用新 token 重連，不轉成需要重新登入', () async {
    statuses = [401];
    final tokens = <String>[];
    final auth = await loggedIn();
    final r = RealtimeService(
      auth: auth,
      clientFactory: () => MockClient.streaming((req, _) async {
        tokens.add(req.headers['Authorization']!);
        final c = _Conn(req, tokens.length == 1 ? 401 : 200);
        conns.add(c);
        return http.StreamedResponse(c.body.stream, c.status);
      }),
      baseUrl: 'https://api.test',
      backoff: (_) => const Duration(milliseconds: 5),
    );
    await settle();
    expect(conns.length, greaterThanOrEqualTo(2));
    expect(auth.isLoggedIn, isTrue);
    r.dispose();
  });

  test('登出後斷開；換帳號後連到新帳號', () async {
    final auth = await loggedIn('A');
    final r = make(auth);
    await settle();
    expect(conns[0].token, 'Bearer tok-A');
    await auth.logout();
    await settle();
    final afterLogout = conns.length;
    expect(afterLogout, 1);
    r.dispose();

    // 換帳號：另一個 sub 登入後，新連線帶新 token
    final auth2 = await loggedIn('B');
    final r2 = make(auth2);
    await settle();
    expect(conns.last.token, 'Bearer tok-B');
    r2.dispose();
  });

  test('閒置逾時（沒收到任何資料）後強制重連', () async {
    final r = make(await loggedIn(), idle: const Duration(milliseconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(conns.length, greaterThanOrEqualTo(2));
    r.dispose();
  });

  test('心跳註解行會重置閒置計時', () async {
    final r = make(await loggedIn(), idle: const Duration(milliseconds: 80));
    await settle();
    for (var i = 0; i < 4; i++) {
      conns[0].push(': ping\n\n');
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    expect(conns, hasLength(1));
    r.dispose();
  });

  test('connected：每次連上都通知（含第一次），斷線不通知，isConnected 跟著變', () async {
    final r = make(await loggedIn());
    var n = 0;
    r.connected.addListener(() => n++);
    await settle();
    expect(n, 1);
    expect(r.isConnected, isTrue);
    await conns[0].end();
    await settle();
    expect(conns.length, greaterThanOrEqualTo(2));
    expect(n, 2);
    expect(r.isConnected, isTrue);
    r.dispose();
  });

  test('connected：401 不算連上；登出後 isConnected 為 false', () async {
    statuses = [401];
    final auth = await loggedIn();
    final r = make(auth);
    var n = 0;
    r.connected.addListener(() => n++);
    await settle();
    expect(n, 1); // 第一次 401，重試後才連上
    expect(r.isConnected, isTrue);
    await auth.logout();
    await settle();
    expect(r.isConnected, isFalse);
    r.dispose();
  });
}
