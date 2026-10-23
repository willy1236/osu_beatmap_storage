import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'friend_service.dart';
import 'lazer_detector.dart';
import 'realtime_service.dart';

/// 上線狀態：偵測 osu!lazer 並回報（`PUT /social/presence`）、公開開關（`/social/settings`），
/// 並把好友的 `presence` 事件套用到 [FriendService]。
///
/// - 登入後每 [interval] 偵測一次，結果與上次回報的不同才回報
/// - 後端要求先連上 SSE 才能回報 playing（沒有連線時視同 idle），斷線立刻視為 idle、沒有寬限，
///   所以只在 [RealtimeService] 已連上時回報；每次連上都把基準重設為 idle（新連線的狀態一定是 idle）
///   再偵測一次，等於重連後補送目前狀態
/// - 回報失敗不重試也不彈窗，下一輪偵測會再送
/// - 登出時不回報 idle（token 已清掉）；後端在最後一條 SSE 斷開時視同 idle
/// - 關閉開關時除了更新設定，也回報 idle
class PresenceService extends ChangeNotifier {
  PresenceService({
    ApiClient? api,
    AuthService? auth,
    RealtimeService? realtime,
    FriendService? friends,
    LazerDetector? detector,
    Duration? interval,
  }) : _api = api ?? ApiClient.instance,
       _auth = auth ?? AuthService.instance,
       _realtime = realtime ?? RealtimeService.instance,
       _friends = friends ?? FriendService.instance,
       _detector = detector ?? WindowsLazerDetector(),
       _interval = interval ?? const Duration(seconds: 5) {
    _auth.addListener(_onAuthChanged);
    _realtime.connected.addListener(_onConnected);
    _realtime.resyncRequested.addListener(_onResync);
    _cancelPresence = _realtime.on('presence', _onPresence);
    _onAuthChanged();
  }

  static final PresenceService instance = PresenceService();

  final ApiClient _api;
  final AuthService _auth;
  final RealtimeService _realtime;
  final FriendService _friends;
  final LazerDetector _detector;
  final Duration _interval;
  late final void Function() _cancelPresence;

  Timer? _timer;
  String? _sub;
  int _generation = 0;
  bool _visible = true;
  bool _visibleLoaded = false;
  bool _reported = false; // 後端目前記得的狀態（新連線一定是 idle）
  bool _ticking = false;
  bool _tickAgain = false;

  /// 是否對好友公開上線狀態；讀到設定前為預設值 true，見 [visibleLoaded]
  bool get visible => _visible;
  bool get visibleLoaded => _visibleLoaded;

  void _onAuthChanged() {
    final sub = _auth.isLoggedIn ? _auth.sub : null;
    if (sub == _sub) return;
    _sub = sub;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _reported = false;
    _visible = true;
    _visibleLoaded = false;
    notifyListeners();
    if (sub != null) {
      _timer = Timer.periodic(_interval, (_) => tick());
      unawaited(tick());
    }
  }

  Future<void> _loadSettings(int gen) async {
    try {
      final resp = await _api.send('GET', '/social/settings');
      if (gen != _generation || resp.statusCode != 200) return;
      final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map;
      _visible = body['presence_visible'] != false;
      _visibleLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Presence 讀取設定失敗：$e');
    }
  }

  void _onConnected() {
    _reported = false;
    unawaited(tick());
  }

  void _onResync() => unawaited(_friends.refresh());

  void _onPresence(Map<String, dynamic> data) {
    final id = data['account_id'];
    if (id is! String) return;
    _friends.setPlaying(id, data['playing'] == true);
  }

  /// 偵測一次，與上次回報不同才回報；執行中再次呼叫會在這次結束後再跑一次
  @visibleForTesting
  Future<void> tick() async {
    if (_ticking) {
      _tickAgain = true;
      return;
    }
    _ticking = true;
    try {
      do {
        _tickAgain = false;
        await _tickOnce();
      } while (_tickAgain);
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tickOnce() async {
    final gen = _generation;
    if (!_auth.isLoggedIn || !_realtime.isConnected) return;
    // 沒讀到設定就不回報：伺服器上可能已經關閉；讀取失敗時下一輪再試
    if (!_visibleLoaded) await _loadSettings(gen);
    if (gen != _generation || !_visibleLoaded || !_visible) return;
    bool playing;
    try {
      playing = await _detector.isRunning();
    } catch (e) {
      debugPrint('Presence 偵測失敗：$e');
      return;
    }
    if (gen != _generation || playing == _reported) return;
    if (await _put(playing) && gen == _generation) _reported = playing;
  }

  Future<bool> _put(bool playing) async {
    try {
      final resp = await _api.send(
        'PUT',
        '/social/presence',
        jsonBody: {'status': playing ? 'playing' : 'idle'},
      );
      return resp.statusCode == 204 || resp.statusCode == 200;
    } catch (e) {
      debugPrint('Presence 回報失敗：$e');
      return false;
    }
  }

  /// 開關上線狀態；成功回傳 true。關閉時一併回報 idle
  Future<bool> setVisible(bool value) async {
    try {
      final resp = await _api.send(
        'PUT',
        '/social/settings',
        jsonBody: {'presence_visible': value},
      );
      if (resp.statusCode != 200) return false;
    } catch (e) {
      debugPrint('Presence 更新設定失敗：$e');
      return false;
    }
    _visible = value;
    _visibleLoaded = true;
    notifyListeners();
    if (!value) {
      if (await _put(false)) _reported = false;
    } else {
      unawaited(tick());
    }
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auth.removeListener(_onAuthChanged);
    _realtime.connected.removeListener(_onConnected);
    _realtime.resyncRequested.removeListener(_onResync);
    _cancelPresence();
    super.dispose();
  }
}
