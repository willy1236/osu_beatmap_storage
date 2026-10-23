import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/cloud_entry.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'cloud_presence_service.dart';
import 'friend_service.dart';
import 'realtime_service.dart';

/// 一次推送最多幾張、附言最多幾字（與後端契約一致）
const kPushEntriesMax = 100;
const kPushMessageMax = 200;

/// 收件匣讀取筆數上限；null 表示不傳 limit（後端回傳全部）。之後要限量改這裡
const int? kInboxLimit = null;

/// 收件匣裡的一筆推送
class PushItem {
  const PushItem({
    required this.id,
    required this.from,
    required this.message,
    required this.entries,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final FriendPeer from;
  final String message;
  final List<CloudEntry> entries;
  final DateTime? createdAt;
  final bool read;

  PushItem copyWith({bool? read}) => PushItem(
    id: id,
    from: from,
    message: message,
    entries: entries,
    createdAt: createdAt,
    read: read ?? this.read,
  );

  static PushItem fromJson(Map<String, dynamic> j) => PushItem(
    id: j['id'] as String,
    from: FriendPeer.fromJson(j['from'] as Map<String, dynamic>, 'created_at'),
    message: j['message'] as String? ?? '',
    entries: [
      for (final e in j['entries'] as List)
        CloudEntry.fromJson(e as Map<String, dynamic>),
    ],
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
    read: j['read'] as bool? ?? false,
  );
}

enum PushSendStatus { ok, notFriend, invalid, failed }

/// 送出推送的結果；不丟例外
class PushSendResult {
  const PushSendResult(
    this.status, {
    this.message,
    this.notFriendIds = const [],
  });

  final PushSendStatus status;
  final String? message;

  /// [PushSendStatus.notFriend] 時，後端列出的非好友 account_id
  final List<String> notFriendIds;

  bool get ok => status == PushSendStatus.ok;
}

enum CollectStatus { ok, rateLimited, failed }

/// 收進我的清單的結果；不丟例外
class CollectResult {
  const CollectResult(
    this.status, {
    this.inserted = 0,
    this.updated = 0,
    this.message,
  });

  final CollectStatus status;
  final int inserted;
  final int updated;
  final String? message;

  bool get ok => status == CollectStatus.ok;
}

/// 推送與收件匣（`/osu/pushes`）。
///
/// - 登入後自動讀取，登出或換帳號時清掉（寫法同 [FriendService]）
/// - 後端的列表直接帶完整圖譜；沒有未讀數端點，[unreadCount] 由列表的 `read` 算出
/// - 訂閱 [RealtimeService.resyncRequested]（重連成功）時整份重讀，只更新列表與紅點
/// - 收到 SSE `push` 事件的人（T-09）呼叫 [refresh] 重讀，事件本身不帶圖譜
class PushService extends ChangeNotifier {
  PushService({
    ApiClient? api,
    AuthService? auth,
    FriendService? friends,
    RealtimeService? realtime,
    void Function()? onCollected,
  }) : _api = api ?? ApiClient.instance,
       _auth = auth ?? AuthService.instance,
       _friends = friends,
       _realtime = realtime,
       _onCollected =
           onCollected ?? (() => CloudPresenceService.instance.refresh()) {
    _auth.addListener(_onAuthChanged);
    _realtime?.resyncRequested.addListener(_onResync);
    _onAuthChanged();
  }

  /// 單例會訂閱 [RealtimeService.instance] 的重連訊號；測試建立的實例預設不訂閱
  static final PushService instance = PushService(
    realtime: RealtimeService.instance,
  );

  final ApiClient _api;
  final AuthService _auth;
  final FriendService? _friends;
  final RealtimeService? _realtime;
  final void Function() _onCollected;

  FriendService get _friendService => _friends ?? FriendService.instance;

  List<PushItem> _items = const [];
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  String? _sub;
  Future<void>? _running;
  bool _again = false;

  /// 正在送 markRead 的 id，以及成功後等在途讀取結束前仍要保持已讀的 id：
  /// 在途的 GET 可能是 markRead 之前發出的，回應不能把已讀蓋回未讀
  final Set<String> _readHold = {};

  /// 新到舊
  List<PushItem> get items => _items;
  int get unreadCount => _items.where((p) => !p.read).length;
  bool get loaded => _loaded;
  bool get loading => _loading;

  /// 最近一次讀取失敗的說明；成功後清掉
  String? get error => _error;

  /// 重新讀取收件匣；讀取中再次呼叫時，等這次結束後再讀一次
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
      List<PushItem>? items;
      try {
        final resp = await _api.send(
          'GET',
          kInboxLimit == null
              ? '/osu/pushes'
              : '/osu/pushes?limit=$kInboxLimit',
        );
        if (resp.statusCode != 200) {
          err = _errorText(resp.statusCode, _errCode(resp), '讀取失敗');
        } else {
          final body = _decode(resp);
          items = [
            for (final e in body['pushes'] as List)
              PushItem.fromJson(e as Map<String, dynamic>),
          ];
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
        _items = [
          for (final p in items!)
            _readHold.contains(p.id) && !p.read ? p.copyWith(read: true) : p,
        ];
        _loaded = true;
        _error = null;
      } else {
        _error = err;
      }
      notifyListeners();
    } while (_again);
    _readHold.clear();
  }

  /// `POST /osu/pushes`。[entries] 的 OnlineID 須大於 0、張數與附言長度須在上限內
  /// （本機先擋，不送出）。後端 403 `not_friend` 時，提示裡的 id 以好友列表反查代號
  Future<PushSendResult> send({
    required List<String> toAccountIds,
    required String message,
    required List<CloudEntry> entries,
  }) async {
    if (toAccountIds.isEmpty) {
      return const PushSendResult(PushSendStatus.invalid, message: '請選擇至少一位好友');
    }
    if (entries.isEmpty) {
      return const PushSendResult(PushSendStatus.invalid, message: '請選擇至少一個圖譜');
    }
    if (entries.length > kPushEntriesMax) {
      return const PushSendResult(
        PushSendStatus.invalid,
        message: '一次最多推送 $kPushEntriesMax 張',
      );
    }
    if (message.length > kPushMessageMax) {
      return const PushSendResult(
        PushSendStatus.invalid,
        message: '附言最多 $kPushMessageMax 字',
      );
    }
    if (entries.any((e) => e.onlineId <= 0)) {
      return const PushSendResult(
        PushSendStatus.invalid,
        message: '沒有 OnlineID 的圖譜無法推送',
      );
    }
    try {
      final resp = await _api.send(
        'POST',
        '/osu/pushes',
        jsonBody: {
          'to': toAccountIds,
          'message': message,
          'entries': [for (final e in entries) e.toJson()],
        },
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return const PushSendResult(PushSendStatus.ok);
      }
      final code = _errCode(resp);
      if (resp.statusCode == 403 && code == 'not_friend') {
        final ids = _idsIn(_errDescription(resp));
        return PushSendResult(
          PushSendStatus.notFriend,
          notFriendIds: ids,
          message: '以下的人不是你的好友，沒有送出：${ids.map(_nameOf).join('、')}',
        );
      }
      if (resp.statusCode == 422) {
        return const PushSendResult(
          PushSendStatus.invalid,
          message: '推送內容不符合規定（最多 $kPushEntriesMax 張、附言最多 $kPushMessageMax 字）',
        );
      }
      return PushSendResult(
        PushSendStatus.failed,
        message: _errorText(resp.statusCode, code, '推送失敗'),
      );
    } on NotSignedInException catch (e) {
      return PushSendResult(PushSendStatus.failed, message: '$e');
    } on TimeoutException {
      return const PushSendResult(PushSendStatus.failed, message: '推送失敗：連線逾時');
    } catch (e) {
      return PushSendResult(PushSendStatus.failed, message: '推送失敗：$e');
    }
  }

  /// `POST /osu/pushes/{id}/read`：先在本機標為已讀，失敗時還原；已讀的不重送
  Future<bool> markRead(String id) async {
    final i = _items.indexWhere((p) => p.id == id);
    if (i < 0) return false;
    if (_items[i].read) return true;
    _readHold.add(id);
    _setRead(id, true);
    final ok = await _simple(
      'POST',
      '/osu/pushes/${Uri.encodeComponent(id)}/read',
    );
    if (!ok) {
      _readHold.remove(id);
      _setRead(id, false);
    } else if (_running != null) {
      // 在途的讀取可能早於這次標記：它結束後再讀一次，期間 [_readHold] 保持已讀
      _again = true;
    } else {
      _readHold.remove(id);
    }
    return ok;
  }

  void _setRead(String id, bool read) {
    final i = _items.indexWhere((p) => p.id == id);
    if (i < 0) return;
    _items = [..._items]..[i] = _items[i].copyWith(read: read);
    notifyListeners();
  }

  /// `POST /osu/pushes/{id}/collect`：整筆併進自己的雲端清單，後端每分鐘限一次
  Future<CollectResult> collect(String id) async {
    try {
      final resp = await _api.send(
        'POST',
        '/osu/pushes/${Uri.encodeComponent(id)}/collect',
      );
      if (resp.statusCode == 200) {
        try {
          final body = _decode(resp);
          final r = CollectResult(
            CollectStatus.ok,
            inserted: body['inserted'] as int,
            updated: body['updated'] as int,
          );
          _onCollected();
          return r;
        } catch (_) {
          return const CollectResult(
            CollectStatus.failed,
            message: '收進清單失敗：伺服器回應格式錯誤',
          );
        }
      }
      if (resp.statusCode == 429) {
        return const CollectResult(CollectStatus.rateLimited, message: '請稍後再試');
      }
      if (resp.statusCode == 404) {
        await refresh();
        return const CollectResult(CollectStatus.failed, message: '這筆推送已不存在');
      }
      return CollectResult(
        CollectStatus.failed,
        message: _errorText(resp.statusCode, _errCode(resp), '收進清單失敗'),
      );
    } on NotSignedInException catch (e) {
      return CollectResult(CollectStatus.failed, message: '$e');
    } on TimeoutException {
      return const CollectResult(CollectStatus.failed, message: '收進清單失敗：連線逾時');
    } catch (e) {
      return CollectResult(CollectStatus.failed, message: '收進清單失敗：$e');
    }
  }

  /// `DELETE /osu/pushes/{id}`：只刪自己收件匣的那一份。成功（含已不存在）後從本機列表移除
  Future<bool> delete(String id) async {
    try {
      final resp = await _api.send(
        'DELETE',
        '/osu/pushes/${Uri.encodeComponent(id)}',
      );
      if ((resp.statusCode >= 200 && resp.statusCode < 300) ||
          resp.statusCode == 404) {
        _items = _items.where((p) => p.id != id).toList();
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _simple(String method, String path) async {
    try {
      final resp = await _api.send(method, path);
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  String _nameOf(String id) {
    final lower = id.toLowerCase();
    for (final p in _friendService.friends) {
      if (p.accountId.toLowerCase() == lower && p.username.isNotEmpty) {
        return p.username;
      }
    }
    return id;
  }

  static final _uuid = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  static List<String> _idsIn(String? description) => [
    for (final m in _uuid.allMatches(description ?? '')) m.group(0)!,
  ];

  static Map<String, dynamic> _decode(http.Response resp) =>
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

  static String? _errCode(http.Response resp) {
    try {
      return _decode(resp)['err'] as String?;
    } catch (_) {
      return null;
    }
  }

  static String? _errDescription(http.Response resp) {
    try {
      return _decode(resp)['description'] as String?;
    } catch (_) {
      return null;
    }
  }

  static String _errorText(int status, String? err, String what) {
    final code =
        err ??
        switch (status) {
          401 => 'unauthorized',
          429 => 'rate_limited',
          503 => 'unavailable',
          _ => null,
        };
    return switch (code) {
      'unauthorized' => '登入已失效，請重新登入',
      'rate_limited' => '請稍後再試',
      'unavailable' => '服務暫時無法使用，請稍後再試',
      _ => '$what（HTTP $status）',
    };
  }

  void _onResync() {
    if (_auth.isLoggedIn) unawaited(refresh());
  }

  void _onAuthChanged() {
    final sub = _auth.isLoggedIn ? _auth.sub : null;
    if (sub == _sub) return;
    _sub = sub;
    final had = _loaded || _items.isNotEmpty || _error != null;
    _items = const [];
    _readHold.clear();
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
