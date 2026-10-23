import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:osu_beatmap_storage/services/api_client.dart';
import 'package:osu_beatmap_storage/services/auth_service.dart';

class MemStore implements AuthTokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

class MemPrefs implements AuthPrefs {
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

const meId = 'aaaaaaaa-0000-0000-0000-000000000001';
const bId = 'bbbbbbbb-0000-0000-0000-000000000002';
const cId = 'cccccccc-0000-0000-0000-000000000003';
const dId = 'dddddddd-0000-0000-0000-000000000004';

AuthService makeAuth({bool loggedIn = true}) {
  final s = MemStore();
  final p = MemPrefs();
  if (loggedIn) {
    p.account = (sub: meId, username: 'me', picture: null);
    s.value = jsonEncode({
      'access': 'a',
      'refresh': 'r',
      'expires_at': DateTime(2099).millisecondsSinceEpoch,
    });
  }
  return AuthService(
    tokenStore: s,
    prefs: p,
    httpClient: MockClient((_) async => http.Response('', 200)),
  );
}

ApiClient makeApi(Future<http.Response> Function(http.Request r) handler) =>
    ApiClient(
      httpClient: MockClient(handler),
      tokenProvider: () async => 'tok',
      refreshToken: (_) async => null,
      onUnauthorized: () async {},
      baseUrl: 'https://api.test',
    );

http.Response jsonResp(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> peerJson(
  String id,
  String name, {
  String timeKey = 'created_at',
  String? picture,
}) => {
  'account_id': id,
  'username': name,
  'picture': picture,
  timeKey: '2026-10-01T00:00:00Z',
};

/// 假的好友後端：[override] 回 null 表示交給預設行為（列表讀取，其餘 204）
class FakeFriendBackend {
  final calls = <http.Request>[];
  List<dynamic> friends = [];
  Map<String, List<dynamic>> requests = {'incoming': [], 'outgoing': []};
  http.Response? Function(http.Request r)? override;

  Future<http.Response> handle(http.Request r) async {
    calls.add(r);
    final o = override?.call(r);
    if (o != null) return o;
    if (r.method == 'GET' && r.url.path == '/social/friends') {
      return jsonResp({'friends': friends});
    }
    if (r.method == 'GET' && r.url.path == '/social/requests') {
      return jsonResp(requests);
    }
    return http.Response('', 204);
  }

  ApiClient get api => makeApi(handle);
}
