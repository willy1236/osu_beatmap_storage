import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_service.dart';
import 'friend_service.dart';

/// 後端規定每人未使用的邀請連結上限（`invite_link_limit`）
const kMaxInviteLinks = 20;

/// 一條還沒用過的好友邀請連結
class InviteLink {
  const InviteLink({required this.token, this.createdAt});

  final String token;
  final DateTime? createdAt;
}

/// 預覽連結的結果：成功時有 [owner]，失敗時有 [code] 與 [message]
class InvitePreview {
  const InvitePreview.ok(FriendPeer this.owner) : code = null, message = null;
  const InvitePreview.failed({this.code, required String this.message})
    : owner = null;

  final FriendPeer? owner;
  final String? code;
  final String? message;

  bool get ok => owner != null;
}

/// 操作結果；[token] 只在 [InviteLinkService.create] 成功時有值
class InviteActionResult {
  const InviteActionResult.ok({this.token}) : code = null, message = null;
  const InviteActionResult.failed({this.code, required String this.message})
    : token = null;

  final String? token;
  final String? code;
  final String? message;

  bool get ok => message == null;
}

/// 好友邀請連結（`/social/invite-links`）：列出未使用的、產生、撤銷、預覽擁有者、接受。
///
/// - 列表由好友頁的邀請連結區塊開啟時讀取；登出或換帳號時清掉
/// - 接受之後重讀好友列表（不樂觀更新：被擁有者封鎖時後端回應像成功，但沒成為好友）
/// - 不丟例外，失敗以 [InviteActionResult] / [InvitePreview] 回報
class InviteLinkService extends ChangeNotifier {
  InviteLinkService({
    ApiClient? api,
    AuthService? auth,
    Future<void> Function()? refreshFriends,
  }) : _api = api ?? ApiClient.instance,
       _auth = auth ?? AuthService.instance,
       _refreshFriends =
           refreshFriends ?? (() => FriendService.instance.refresh()) {
    _auth.addListener(_onAuthChanged);
    _sub = _auth.isLoggedIn ? _auth.sub : null;
  }

  static final InviteLinkService instance = InviteLinkService();

  final ApiClient _api;
  final AuthService _auth;
  final Future<void> Function() _refreshFriends;

  List<InviteLink> _links = const [];
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  String? _sub;

  List<InviteLink> get links => _links;
  bool get loaded => _loaded;
  bool get loading => _loading;

  /// 最近一次讀取失敗的說明；成功後清掉
  String? get error => _error;

  /// 讀取未使用的連結；失敗時保留上一次的結果並設 [error]
  Future<void> refresh() async {
    if (!_auth.isLoggedIn || _loading) return;
    final sub = _auth.sub;
    _loading = true;
    notifyListeners();
    String? err;
    List<InviteLink>? links;
    try {
      final resp = await _api.send('GET', '/social/invite-links');
      if (resp.statusCode == 200) {
        links = [
          for (final e in _decode(resp)['links'] as List)
            _link(e as Map<String, dynamic>),
        ];
      } else {
        err = _errorFor(resp.statusCode, _errCode(resp), '讀取失敗').$2;
      }
    } on NotSignedInException catch (e) {
      err = '$e';
    } on TimeoutException {
      err = '讀取失敗：連線逾時';
    } catch (e) {
      err = '讀取失敗：$e';
    }
    _loading = false;
    // 讀取期間登出或換了帳號：結果不屬於目前的域民
    if (!_auth.isLoggedIn || _auth.sub != sub) {
      notifyListeners();
      return;
    }
    if (err == null) {
      _links = links!;
      _loaded = true;
      _error = null;
    } else {
      _error = err;
    }
    notifyListeners();
  }

  /// `POST /social/invite-links`：產生一條新連結
  Future<InviteActionResult> create() async {
    final r = await _call('POST', '/social/invite-links');
    if (r.resp == null) return r.failure!;
    try {
      final token = _decode(r.resp!)['token'] as String;
      await refresh();
      return InviteActionResult.ok(token: token);
    } catch (_) {
      return const InviteActionResult.failed(message: '伺服器回應格式錯誤');
    }
  }

  /// `DELETE /social/invite-links/{token}`：撤銷（後端冪等，已失效也回成功）
  Future<InviteActionResult> revoke(String token) async {
    final r = await _call(
      'DELETE',
      '/social/invite-links/${Uri.encodeComponent(token)}',
    );
    if (r.resp == null) return r.failure!;
    await refresh();
    return const InviteActionResult.ok();
  }

  /// `GET /social/invite-links/{token}`：連結擁有者，不消耗連結
  Future<InvitePreview> preview(String token) async {
    final r = await _call(
      'GET',
      '/social/invite-links/${Uri.encodeComponent(token)}',
    );
    if (r.resp == null) {
      return InvitePreview.failed(
        code: r.failure!.code,
        message: r.failure!.message!,
      );
    }
    try {
      return InvitePreview.ok(FriendPeer.fromJson(_decode(r.resp!), 'since'));
    } catch (_) {
      return const InvitePreview.failed(message: '伺服器回應格式錯誤');
    }
  }

  /// `POST /social/invite-links/{token}/accept`：直接成為好友，之後重讀好友列表
  Future<InviteActionResult> accept(String token) async {
    final r = await _call(
      'POST',
      '/social/invite-links/${Uri.encodeComponent(token)}/accept',
    );
    // 失敗（例如連結剛被用掉）時本機好友列表也可能已過期，一樣重讀
    if (r.failure?.code != 'unauthorized') await _refreshFriends();
    return r.resp == null ? r.failure! : const InviteActionResult.ok();
  }

  Future<({http.Response? resp, InviteActionResult? failure})> _call(
    String method,
    String path,
  ) async {
    try {
      final resp = await _api.send(method, path);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return (resp: resp, failure: null);
      }
      final e = _errorFor(resp.statusCode, _errCode(resp), '操作失敗');
      return (
        resp: null,
        failure: InviteActionResult.failed(code: e.$1, message: e.$2),
      );
    } on NotSignedInException catch (e) {
      return (
        resp: null,
        failure: InviteActionResult.failed(code: 'unauthorized', message: '$e'),
      );
    } on TimeoutException {
      return (
        resp: null,
        failure: const InviteActionResult.failed(message: '操作失敗：連線逾時'),
      );
    } catch (e) {
      return (
        resp: null,
        failure: InviteActionResult.failed(message: '操作失敗：$e'),
      );
    }
  }

  static InviteLink _link(Map<String, dynamic> j) => InviteLink(
    token: j['token'] as String,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
  );

  static Map<String, dynamic> _decode(http.Response resp) =>
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

  static String? _errCode(http.Response resp) {
    try {
      return _decode(resp)['err'] as String?;
    } catch (_) {
      return null;
    }
  }

  static (String?, String) _errorFor(int status, String? err, String what) {
    final code =
        err ??
        switch (status) {
          401 => 'unauthorized',
          404 => 'not_found',
          429 => 'rate_limited',
          503 => 'unavailable',
          _ => null,
        };
    return (
      code,
      switch (code) {
        'not_found' => '邀請連結已失效',
        'already_friends' => '你們已經是好友',
        'friend_limit' => '好友已達上限',
        'cannot_friend_self' => '不能使用自己的邀請連結',
        'blocked_by_you' => '你已封鎖這位域民',
        'invite_link_limit' => '未使用的邀請連結最多 $kMaxInviteLinks 條，請先撤銷不用的',
        'unauthorized' => '登入已失效，請重新登入',
        'rate_limited' => '操作太頻繁，請稍後再試',
        'unavailable' => '服務暫時無法使用，請稍後再試',
        _ => '$what（HTTP $status）',
      },
    );
  }

  void _onAuthChanged() {
    final sub = _auth.isLoggedIn ? _auth.sub : null;
    if (sub == _sub) return;
    _sub = sub;
    final had = _loaded || _links.isNotEmpty || _error != null;
    _links = const [];
    _loaded = false;
    _error = null;
    if (had) notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
