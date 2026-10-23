import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import 'auth_service.dart';

typedef RealtimeHandler = void Function(Map<String, dynamic> data);

/// 後端即時事件通道（SSE，`GET /social/events`）的桌面端。
///
/// - 登入後保持一條連線；登出或換帳號時斷開，換帳號後連到新帳號
/// - 斷線（網路錯誤、串流結束、閒置逾時）後退避重連；重連成功時發出 [resyncRequested]，
///   訂閱者整份重新讀取（後端不補送斷線期間的事件）。同一次登入的第一次連線不發
/// - 每次連線前才向 [AuthService] 取 token，所以 refresh 後的重連用新 token
/// - 任何失敗都只記 log，不彈窗、不影響其他功能
/// - 盡早建立 [instance]（`main()`），登入還原後就會連線
class RealtimeService {
  RealtimeService({
    AuthService? auth,
    http.Client Function()? clientFactory,
    String? baseUrl,
    Duration? idleTimeout,
    Duration? connectTimeout,
    Duration Function(int attempt)? backoff,
    Random? random,
  }) : _auth = auth ?? AuthService.instance,
       _clientFactory = clientFactory ?? http.Client.new,
       _baseUrl = baseUrl ?? kApiBase,
       _idleTimeout = idleTimeout ?? const Duration(seconds: 90),
       _connectTimeout = connectTimeout ?? const Duration(seconds: 30),
       _random = random ?? Random() {
    _backoff = backoff ?? _defaultBackoff;
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  static final RealtimeService instance = RealtimeService();

  final AuthService _auth;
  final http.Client Function() _clientFactory;
  final String _baseUrl;

  /// 後端心跳 30 秒一次；超過這段時間完全沒收到資料就視為半開連線，強制重連
  final Duration _idleTimeout;
  final Duration _connectTimeout;
  final Random _random;
  late final Duration Function(int attempt) _backoff;

  final _resync = _Signal();
  final Map<String, Set<RealtimeHandler>> _handlers = {};

  String? _sub;
  int _generation = 0;
  http.Client? _client;

  /// 重連成功時通知；訂閱者整份重新讀取
  Listenable get resyncRequested => _resync;

  /// 訂閱事件型別（SSE 的 `event:` 欄位）；回傳取消訂閱的函式
  void Function() on(String type, RealtimeHandler handler) {
    _handlers.putIfAbsent(type, () => {}).add(handler);
    return () {
      final set = _handlers[type];
      if (set == null) return;
      set.remove(handler);
      if (set.isEmpty) _handlers.remove(type);
    };
  }

  Duration _defaultBackoff(int attempt) {
    final capped = min(30000, 1000 * (1 << min(attempt, 5)));
    // 一半固定、一半隨機，避免後端重啟時所有程式同時重連
    return Duration(
      milliseconds: capped ~/ 2 + _random.nextInt(capped ~/ 2 + 1),
    );
  }

  void _onAuthChanged() {
    final sub = _auth.isLoggedIn ? _auth.sub : null;
    if (sub == _sub) return;
    _sub = sub;
    _stop();
    if (sub != null) unawaited(_run(_generation));
  }

  void _stop() {
    _generation++;
    _client?.close();
    _client = null;
  }

  Future<void> _run(int gen) async {
    var attempt = 0;
    var everConnected = false;
    while (gen == _generation) {
      http.Client? client;
      try {
        final token = await _auth.accessToken();
        if (gen != _generation) return;
        if (token == null) throw const _Retry('沒有可用的 token');
        client = _clientFactory();
        _client = client;
        final req = http.Request('GET', Uri.parse('$_baseUrl/social/events'))
          ..headers['Authorization'] = 'Bearer $token'
          ..headers['Accept'] = 'text/event-stream'
          ..headers['Cache-Control'] = 'no-cache';
        final resp = await client.send(req).timeout(_connectTimeout);
        if (gen != _generation) return;
        if (resp.statusCode == 401) {
          // token 被拒：強制 refresh，退避後的下一輪會取到新 token；不動登入狀態
          await _auth.refreshAccessToken(rejected: token);
          throw const _Retry('401');
        }
        if (resp.statusCode != 200) throw _Retry('HTTP ${resp.statusCode}');
        attempt = 0;
        if (everConnected) _resync.fire();
        everConnected = true;
        await _read(resp.stream, gen);
        // 串流正常結束（例如後端重新部署）也當成斷線
      } catch (e) {
        if (gen != _generation) return;
        debugPrint('Realtime 連線中斷：$e');
      } finally {
        client?.close();
        if (identical(_client, client)) _client = null;
      }
      if (gen != _generation) return;
      await Future<void>.delayed(_backoff(attempt++));
    }
  }

  Future<void> _read(Stream<List<int>> bytes, int gen) async {
    final lines = bytes
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(_idleTimeout);
    var event = 'message';
    final data = <String>[];
    await for (final line in lines) {
      if (gen != _generation) return;
      if (line.isEmpty) {
        if (data.isNotEmpty) _dispatch(event, data.join('\n'));
        event = 'message';
        data.clear();
        continue;
      }
      if (line.startsWith(':')) continue; // 註解行（心跳）
      final i = line.indexOf(':');
      final field = i < 0 ? line : line.substring(0, i);
      var value = i < 0 ? '' : line.substring(i + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'event') {
        event = value;
      } else if (field == 'data') {
        data.add(value);
      }
    }
  }

  void _dispatch(String type, String raw) {
    final set = _handlers[type];
    if (set == null) return;
    final Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      map = decoded;
    } on FormatException {
      return;
    }
    for (final handler in List.of(set)) {
      try {
        handler(map);
      } catch (e) {
        debugPrint('Realtime handler 失敗（$type）：$e');
      }
    }
  }

  @visibleForTesting
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _stop();
    _resync.dispose();
  }
}

class _Retry implements Exception {
  const _Retry(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}
