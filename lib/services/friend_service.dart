import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_service.dart';
import 'realtime_service.dart';

/// 好友或邀請列表上的一位域民
class FriendPeer {
  const FriendPeer({
    required this.accountId,
    required this.username,
    this.picture,
    this.time,
    this.playing = false,
    this.canBrowse = false,
  });

  final String accountId;

  /// 目前的代號；後端查不到域民資料時為空字串，顯示用 [displayName]
  final String username;
  final String? picture;

  /// 好友列表為成為好友的時間，邀請列表為送出時間
  final DateTime? time;

  /// 正在遊玩 osu!lazer；只有好友列表會有，對方關掉上線狀態時一律 false
  final bool playing;

  /// 對方開放好友瀏覽清單（`/osu/friends/browsable`）；只有好友列表會帶，預設 false
  final bool canBrowse;

  FriendPeer withCanBrowse(bool v) => FriendPeer(
    accountId: accountId,
    username: username,
    picture: picture,
    time: time,
    playing: playing,
    canBrowse: v,
  );

  FriendPeer withPlaying(bool v) => FriendPeer(
    accountId: accountId,
    username: username,
    picture: picture,
    time: time,
    playing: v,
    canBrowse: canBrowse,
  );

  String get displayName => username.isEmpty ? '（未知的域民）' : username;

  static FriendPeer fromJson(Map<String, dynamic> j, String timeKey) {
    final pic = j['picture'] as String?;
    return FriendPeer(
      accountId: j['account_id'] as String,
      username: j['username'] as String? ?? '',
      picture: (pic == null || pic.isEmpty) ? null : pic,
      time: DateTime.tryParse(j[timeKey] as String? ?? ''),
      playing: j['playing'] == true,
    );
  }
}

/// 與某位域民目前的好友關係
enum FriendRelation { none, self, friends, outgoing, incoming }

enum FriendActionStatus { sent, friends, done, failed }

/// 送出、接受、拒絕、取消邀請的結果；不丟例外
class FriendActionResult {
  const FriendActionResult(this.status, {this.code, this.message});

  final FriendActionStatus status;

  /// 後端的錯誤碼（`err`），例如 `already_friends`；非後端錯誤時為 null
  final String? code;
  final String? message;

  bool get ok => status != FriendActionStatus.failed;
}

/// 好友、收到與送出的邀請（`/social/*`）。
///
/// - 登入後自動讀取，登出或換帳號時清掉（寫法同 `CloudPresenceService`）
/// - 送出、接受、拒絕、取消之後一律重讀，不樂觀更新：被對方封鎖時後端仍回「已送出」，
///   本機列表以重讀的結果為準
/// - 讀取失敗時保留上一次的結果並設 [error]
/// - 訂閱 [RealtimeService.resyncRequested]（重連成功）時整份重讀，不發通知
class FriendService extends ChangeNotifier {
  FriendService({ApiClient? api, AuthService? auth, RealtimeService? realtime})
    : _api = api ?? ApiClient.instance,
      _auth = auth ?? AuthService.instance,
      _realtime = realtime {
    _auth.addListener(_onAuthChanged);
    _realtime?.resyncRequested.addListener(_onResync);
    _onAuthChanged();
  }

  /// 單例會訂閱 [RealtimeService.instance] 的重連訊號；測試建立的實例預設不訂閱
  static final FriendService instance = FriendService(
    realtime: RealtimeService.instance,
  );

  final ApiClient _api;
  final AuthService _auth;
  final RealtimeService? _realtime;

  List<FriendPeer> _friends = const [];
  List<FriendPeer> _incoming = const [];
  List<FriendPeer> _outgoing = const [];
  List<FriendPeer> _blocks = const [];
  bool _blocksLoaded = false;
  bool _blocksLoading = false;
  String? _blocksError;
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  String? _sub;
  Future<void>? _running;
  bool _again = false;

  List<FriendPeer> get friends => _friends;
  List<FriendPeer> get incoming => _incoming;
  List<FriendPeer> get outgoing => _outgoing;

  /// 封鎖名單；不隨登入自動讀取，進封鎖名單頁時呼叫 [refreshBlocks]
  List<FriendPeer> get blocks => _blocks;
  bool get blocksLoaded => _blocksLoaded;
  bool get blocksLoading => _blocksLoading;
  String? get blocksError => _blocksError;

  /// 已讀到目前登入域民的資料
  bool get loaded => _loaded;
  bool get loading => _loading;

  /// 最近一次讀取失敗的說明；成功後清掉
  String? get error => _error;

  static String _norm(String id) => id.toLowerCase();

  /// 與 [accountId] 的關係；以本機已讀到的列表為準，尚未載入時為 [FriendRelation.none]
  FriendRelation relationOf(String accountId) {
    final id = _norm(accountId);
    final me = _auth.sub;
    if (me != null && _norm(me) == id) return FriendRelation.self;
    bool has(List<FriendPeer> l) => l.any((p) => _norm(p.accountId) == id);
    if (has(_friends)) return FriendRelation.friends;
    if (has(_outgoing)) return FriendRelation.outgoing;
    if (has(_incoming)) return FriendRelation.incoming;
    return FriendRelation.none;
  }

  /// 套用 SSE `presence` 事件：更新好友的遊玩狀態，不重讀。不是好友或沒變就忽略
  void setPlaying(String accountId, bool playing) {
    final id = _norm(accountId);
    final i = _friends.indexWhere((p) => _norm(p.accountId) == id);
    if (i < 0 || _friends[i].playing == playing) return;
    _friends = [..._friends]..[i] = _friends[i].withPlaying(playing);
    notifyListeners();
  }

  /// 重新讀取好友與邀請；讀取中再次呼叫時，等這次結束後再讀一次
  Future<void> refresh() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _load().whenComplete(() => _running = null);
  }

  Future<void> _load() async {
    do {
      _again = false;
      if (!_auth.isLoggedIn) return;
      final sub = _auth.sub;
      _loading = true;
      notifyListeners();
      String? err;
      List<FriendPeer>? friends, incoming, outgoing;
      Set<String> browsable = const {};
      try {
        final r = await Future.wait<Object>([
          _api.send('GET', '/social/friends'),
          _api.send('GET', '/social/requests'),
          _browsableIds(),
        ]);
        browsable = r[2] as Set<String>;
        for (final resp in r.take(2).cast<http.Response>()) {
          if (resp.statusCode != 200) {
            err = _errorFor(resp.statusCode, _errCode(resp), '讀取失敗').$2;
          }
        }
        if (err == null) {
          final f = _decode(r[0] as http.Response);
          final q = _decode(r[1] as http.Response);
          friends = [
            for (final p in _peers(f['friends'], 'since'))
              p.withCanBrowse(browsable.contains(_norm(p.accountId))),
          ];
          incoming = _peers(q['incoming'], 'created_at');
          outgoing = _peers(q['outgoing'], 'created_at');
        }
      } on NotSignedInException catch (e) {
        err = '$e';
      } on TimeoutException {
        err = '讀取失敗：連線逾時';
      } catch (e) {
        err = '讀取失敗：$e';
      }
      _loading = false;
      // 讀取期間登出或換了帳號：結果不屬於目前的域民；換帳號時 _again 已設好，迴圈會再讀一次
      if (!_auth.isLoggedIn || _auth.sub != sub) continue;
      if (err == null) {
        _friends = friends!;
        _incoming = incoming!;
        _outgoing = outgoing!;
        _loaded = true;
        _error = null;
      } else {
        _error = err;
      }
      notifyListeners();
    } while (_again);
  }

  /// `GET /osu/friends/browsable`；失敗時視為沒有人開放（入口不顯示，不拖累好友列表）
  Future<Set<String>> _browsableIds() async {
    try {
      final resp = await _api.send('GET', '/osu/friends/browsable');
      if (resp.statusCode != 200) return const {};
      return {
        for (final id in _decode(resp)['account_ids'] as List)
          _norm(id as String),
      };
    } catch (_) {
      return const {};
    }
  }

  static Map<String, dynamic> _decode(http.Response resp) =>
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

  static List<FriendPeer> _peers(dynamic list, String timeKey) => [
    for (final e in list as List)
      FriendPeer.fromJson(e as Map<String, dynamic>, timeKey),
  ];

  /// `POST /osu/shared/{token}/friend-request`：對分享清單的擁有者送好友邀請
  Future<FriendActionResult> sendViaShare(String token) => _act(
    'POST',
    '/osu/shared/${Uri.encodeComponent(token)}/friend-request',
    notFound: '分享連結已失效',
    sending: true,
    parse: (body) => body['status'] == 'friends'
        ? FriendActionStatus.friends
        : FriendActionStatus.sent,
  );

  /// `POST /social/requests/{from_id}/accept`
  Future<FriendActionResult> accept(String fromId) => _act(
    'POST',
    '/social/requests/${Uri.encodeComponent(fromId)}/accept',
    notFound: '這筆邀請已不存在',
    parse: (_) => FriendActionStatus.friends,
  );

  /// `POST /social/requests/{from_id}/reject`
  Future<FriendActionResult> reject(String fromId) => _act(
    'POST',
    '/social/requests/${Uri.encodeComponent(fromId)}/reject',
    notFound: '這筆邀請已不存在',
  );

  /// `DELETE /social/requests/{to_id}`
  Future<FriendActionResult> cancel(String toId) => _act(
    'DELETE',
    '/social/requests/${Uri.encodeComponent(toId)}',
    notFound: '這筆邀請已不存在',
  );

  /// `POST /social/requests`：對指定域民送好友邀請（對方已邀請過我時直接成為好友）
  Future<FriendActionResult> sendToAccount(String accountId) => _act(
    'POST',
    '/social/requests',
    jsonBody: {'account_id': accountId},
    notFound: '找不到這位域民',
    sending: true,
    parse: (body) => body['status'] == 'friends'
        ? FriendActionStatus.friends
        : FriendActionStatus.sent,
  );

  /// `DELETE /social/friends/{account_id}`
  Future<FriendActionResult> removeFriend(String id) => _act(
    'DELETE',
    '/social/friends/${Uri.encodeComponent(id)}',
    notFound: '找不到這位好友',
  );

  /// `PUT /social/blocks/{account_id}`：封鎖並解除好友關係、移除雙方之間的邀請
  Future<FriendActionResult> block(String id) async {
    final r = await _act(
      'PUT',
      '/social/blocks/${Uri.encodeComponent(id)}',
      notFound: '找不到這位域民',
    );
    if (r.ok && _blocksLoaded) await refreshBlocks();
    return r;
  }

  /// `DELETE /social/blocks/{account_id}`：解除封鎖，好友關係不會恢復
  Future<FriendActionResult> unblock(String id) async {
    final r = await _act(
      'DELETE',
      '/social/blocks/${Uri.encodeComponent(id)}',
      notFound: '找不到這位域民',
    );
    if (r.ok) await refreshBlocks();
    return r;
  }

  /// `GET /social/blocks`；失敗時保留上一次的名單並設 [blocksError]
  Future<void> refreshBlocks() async {
    if (!_auth.isLoggedIn) return;
    final sub = _auth.sub;
    _blocksLoading = true;
    notifyListeners();
    String? err;
    List<FriendPeer>? blocks;
    try {
      final resp = await _api.send('GET', '/social/blocks');
      if (resp.statusCode != 200) {
        err = _errorFor(resp.statusCode, _errCode(resp), '讀取失敗').$2;
      } else {
        blocks = _peers(_decode(resp)['blocks'], 'created_at');
      }
    } on NotSignedInException catch (e) {
      err = '$e';
    } on TimeoutException {
      err = '讀取失敗：連線逾時';
    } catch (e) {
      err = '讀取失敗：$e';
    }
    _blocksLoading = false;
    // 讀取期間登出或換了帳號：結果不屬於目前的域民
    if (!_auth.isLoggedIn || _auth.sub != sub) return;
    if (blocks != null) {
      _blocks = blocks;
      _blocksLoaded = true;
      _blocksError = null;
    } else {
      _blocksError = err;
    }
    notifyListeners();
  }

  Future<FriendActionResult> _act(
    String method,
    String path, {
    Object? jsonBody,
    required String notFound,
    bool sending = false,
    FriendActionStatus Function(Map<String, dynamic> body)? parse,
  }) async {
    FriendActionResult result;
    try {
      final resp = await _api.send(method, path, jsonBody: jsonBody);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        var status = FriendActionStatus.done;
        if (parse != null) {
          try {
            status = parse(_decode(resp));
          } catch (_) {
            return const FriendActionResult(
              FriendActionStatus.failed,
              message: '伺服器回應格式錯誤',
            );
          }
        }
        result = FriendActionResult(status);
      } else {
        final e = _errorFor(
          resp.statusCode,
          _errCode(resp),
          '操作失敗',
          notFound: notFound,
          sending: sending,
        );
        result = FriendActionResult(
          FriendActionStatus.failed,
          code: e.$1,
          message: e.$2,
        );
      }
    } on NotSignedInException catch (e) {
      return FriendActionResult(
        FriendActionStatus.failed,
        code: 'unauthorized',
        message: '$e',
      );
    } on TimeoutException {
      return const FriendActionResult(
        FriendActionStatus.failed,
        message: '操作失敗：連線逾時',
      );
    } catch (e) {
      return FriendActionResult(FriendActionStatus.failed, message: '操作失敗：$e');
    }
    // 成功與失敗都重讀：失敗（例如邀請已被取消）時本機列表可能已過期
    await refresh();
    return result;
  }

  static String? _errCode(http.Response resp) {
    try {
      return _decode(resp)['err'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 後端錯誤碼與 HTTP 狀態對應到 (code, 提示文字)
  static (String?, String) _errorFor(
    int status,
    String? err,
    String what, {
    String notFound = '找不到這筆資料',
    bool sending = false,
  }) {
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
        'already_friends' => '你們已經是好友',
        'friend_limit' => '好友已達上限',
        'cannot_friend_self' => '不能對自己送邀請',
        // 只有「送出邀請」的 429 是邀請次數限制；其他操作與讀取用一般文案
        'rate_limited' => sending ? '今天送出的邀請太多，請稍後再試' : '請求太頻繁，請稍後再試',
        'blocked_by_you' => '你已封鎖這位域民，請先到封鎖名單解除封鎖',
        'cannot_block_self' => '不能封鎖自己',
        'not_found' => notFound,
        'unauthorized' => '登入已失效，請重新登入',
        'unavailable' => '服務暫時無法使用，請稍後再試',
        _ => '$what（HTTP $status）',
      },
    );
  }

  void _onResync() {
    if (_auth.isLoggedIn) unawaited(refresh());
  }

  void _onAuthChanged() {
    final sub = _auth.isLoggedIn ? _auth.sub : null;
    if (sub == _sub) return;
    _sub = sub;
    final had = _loaded || _friends.isNotEmpty || _error != null;
    _friends = _incoming = _outgoing = _blocks = const [];
    _blocksLoaded = false;
    _blocksError = null;
    _loaded = false;
    _error = null;
    if (had) notifyListeners();
    if (sub != null) refresh();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _realtime?.resyncRequested.removeListener(_onResync);
    super.dispose();
  }
}
