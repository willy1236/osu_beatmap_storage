import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
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
  ({String sub, String username, String? picture})? account;
  @override
  Future<({String sub, String username, String? picture})?>
  getAccount() async => account;
  @override
  Future<void> setAccount(
    String? sub,
    String? username, {
    String? picture,
  }) async => account = sub == null
      ? null
      : (sub: sub, username: username ?? '', picture: picture);
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

/// 測試用的 AuthService：sub／登入狀態由測試直接設定，用來走「不經登出直接換帳號」的路徑
class _FakeAuth extends AuthService {
  _FakeAuth(this._subValue);
  String? _subValue;
  @override
  bool get isLoggedIn => _subValue != null;
  @override
  String? get sub => _subValue;
  @override
  Future<String?> accessToken() async =>
      _subValue == null ? null : 'tok-$_subValue';
  void switchTo(String? sub) {
    _subValue = sub;
    notifyListeners();
  }
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

  /// 全部在 fake 時間裡跑：不依賴真實時間，全套並行負載下也不會逾時
  void fakeTest(String name, void Function(FakeAsync async) body) {
    test(name, () => fakeAsync(body));
  }

  /// 在 fake 時間裡等一個 Future 完成
  T await_<T>(FakeAsync async, Future<T> f) {
    late T value;
    var done = false;
    Object? error;
    f.then((v) {
      value = v;
      done = true;
    }, onError: (Object e) => error = e);
    async.flushMicrotasks();
    if (error != null) throw error!;
    expect(done, isTrue, reason: 'Future 沒有完成');
    return value;
  }

  void settle(FakeAsync async) => async.elapse(const Duration(seconds: 1));

  AuthService makeAuth({http.Client? client}) => AuthService(
    tokenStore: store,
    prefs: prefs,
    httpClient: client ?? MockClient((_) async => http.Response('', 200)),
  );

  AuthService loggedIn(
    FakeAsync async, [
    String sub = 'A',
    http.Client? client,
  ]) {
    prefs.account = (sub: sub, username: 'u', picture: null);
    store.value = jsonEncode({
      'access': 'tok-$sub',
      'refresh': 'r',
      'expires_at': DateTime(2099).millisecondsSinceEpoch,
    });
    final auth = makeAuth(client: client);
    await_(async, auth.init());
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

  fakeTest('未登入：不連線', (async) {
    final r = make(makeAuth());
    settle(async);
    expect(conns, isEmpty);
    r.dispose();
  });

  fakeTest('登入後連線，帶 Bearer token 與 SSE header', (async) {
    final r = make(loggedIn(async));
    settle(async);
    expect(conns, hasLength(1));
    expect(conns[0].request.url.toString(), 'https://api.test/social/events');
    expect(conns[0].token, 'Bearer tok-A');
    expect(conns[0].request.headers['Accept'], 'text/event-stream');
    r.dispose();
  });

  fakeTest('事件依型別分派；忽略註解行、壞 JSON、未訂閱型別；可取消訂閱', (async) {
    final r = make(loggedIn(async));
    final got = <Map<String, dynamic>>[];
    final cancel = r.on('push', got.add);
    r.on('push', (_) => throw StateError('handler 壞掉不能影響別人'));
    settle(async);
    conns[0].push(': connected\n\n');
    conns[0].push('event: push\ndata: {"id":"1",');
    conns[0].push('"message":"嗨"}\n\n');
    conns[0].push(': ping\n\nevent: push\ndata: not json\n\n');
    conns[0].push('event: other\ndata: {"x":1}\n\n');
    settle(async);
    expect(got, [
      {'id': '1', 'message': '嗨'},
    ]);
    cancel();
    conns[0].push('event: push\ndata: {"id":"2"}\n\n');
    settle(async);
    expect(got, hasLength(1));
    r.dispose();
  });

  fakeTest('串流結束後重連並發出 resync；第一次連線不發', (async) {
    final r = make(loggedIn(async));
    var resyncs = 0;
    r.resyncRequested.addListener(() => resyncs++);
    settle(async);
    expect(conns, hasLength(1));
    expect(resyncs, 0);
    conns[0].end();
    settle(async);
    expect(conns, hasLength(2));
    expect(resyncs, 1);
    r.dispose();
  });

  fakeTest('連線失敗（5xx）退避重試，成功後才發 resync 且前一次失敗不發', (async) {
    statuses = [200, 503, 200];
    final r = make(loggedIn(async));
    var resyncs = 0;
    r.resyncRequested.addListener(() => resyncs++);
    settle(async);
    conns[0].end();
    settle(async);
    expect(conns.length, 3);
    expect(resyncs, 1);
    r.dispose();
  });

  fakeTest('401：refresh 後用新 token 重連，不轉成需要重新登入', (async) {
    statuses = [401];
    var refreshCalls = 0;
    final auth = loggedIn(
      async,
      'A',
      MockClient((req) async {
        refreshCalls++;
        return http.Response(
          jsonEncode({
            'access_token': 'tok-new',
            'refresh_token': 'r2',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );
    final r = make(auth);
    settle(async);
    expect(refreshCalls, 1);
    expect(conns, hasLength(2));
    expect(conns[0].token, 'Bearer tok-A');
    expect(conns[1].token, 'Bearer tok-new');
    expect(auth.isLoggedIn, isTrue);
    r.dispose();
  });

  fakeTest('登出後斷開', (async) {
    final auth = loggedIn(async, 'A');
    final r = make(auth);
    settle(async);
    expect(conns, hasLength(1));
    expect(conns[0].token, 'Bearer tok-A');
    await_(async, auth.logout());
    settle(async);
    expect(conns, hasLength(1));
    expect(r.isConnected, isFalse);
    r.dispose();
  });

  fakeTest('同一個實例換帳號：舊連線的事件不再分派，新連線帶新帳號 token', (async) {
    final auth = _FakeAuth('A');
    final r = make(auth);
    final got = <String>[];
    r.on('push', (d) => got.add(d['id'] as String));
    settle(async);
    expect(conns, hasLength(1));
    expect(conns[0].token, 'Bearer tok-A');

    // 不經登出直接換成 B
    auth.switchTo('B');
    settle(async);
    expect(conns, hasLength(2));
    expect(conns[1].token, 'Bearer tok-B');
    expect(r.isConnected, isTrue);

    conns[0].push('event: push\ndata: {"id":"old"}\n\n');
    conns[1].push('event: push\ndata: {"id":"new"}\n\n');
    settle(async);
    expect(got, ['new']);

    // 登出後斷開，不再連線
    auth.switchTo(null);
    settle(async);
    expect(r.isConnected, isFalse);
    expect(conns, hasLength(2));
    r.dispose();
  });

  fakeTest('閒置逾時（沒收到任何資料）後強制重連', (async) {
    final r = make(loggedIn(async), idle: const Duration(seconds: 90));
    settle(async);
    expect(conns, hasLength(1));
    async.elapse(const Duration(seconds: 85));
    expect(conns, hasLength(1));
    async.elapse(const Duration(seconds: 10));
    expect(conns.length, greaterThanOrEqualTo(2));
    r.dispose();
  });

  fakeTest('心跳註解行會重置閒置計時', (async) {
    final r = make(loggedIn(async), idle: const Duration(seconds: 90));
    settle(async);
    for (var i = 0; i < 4; i++) {
      conns[0].push(': ping\n\n');
      async.elapse(const Duration(seconds: 60));
    }
    expect(conns, hasLength(1));
    r.dispose();
  });

  fakeTest('connected：每次連上都通知（含第一次），斷線不通知，isConnected 跟著變', (async) {
    final r = make(loggedIn(async));
    var n = 0;
    r.connected.addListener(() => n++);
    settle(async);
    expect(n, 1);
    expect(r.isConnected, isTrue);
    conns[0].end();
    settle(async);
    expect(conns.length, greaterThanOrEqualTo(2));
    expect(n, 2);
    expect(r.isConnected, isTrue);
    r.dispose();
  });

  fakeTest('connected：401 不算連上；登出後 isConnected 為 false', (async) {
    statuses = [401];
    final auth = loggedIn(async);
    final r = make(auth);
    var n = 0;
    r.connected.addListener(() => n++);
    settle(async);
    expect(n, 1); // 第一次 401，重試後才連上
    expect(r.isConnected, isTrue);
    await_(async, auth.logout());
    settle(async);
    expect(r.isConnected, isFalse);
    r.dispose();
  });
}
