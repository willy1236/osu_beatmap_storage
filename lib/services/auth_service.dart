import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../constants.dart';
import 'prefs_service.dart';

/// 登入狀態
enum AuthStatus {
  /// 未登入
  loggedOut,

  /// 已開啟瀏覽器，等待登入完成
  loggingIn,

  /// 已登入
  loggedIn,

  /// 曾登入，但 refresh token 失效（例如帳號被停權），需要重新登入
  reloginRequired,
}

/// token 的存放處（正式環境為 Windows 的安全儲存）
abstract interface class AuthTokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureAuthTokenStore implements AuthTokenStore {
  static const _key = 'auth_tokens';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// 帳號資訊與「剛登出過」旗標的存放處（正式環境為 config.json）
abstract interface class AuthPrefs {
  Future<({String sub, String username})?> getAccount();
  Future<void> setAccount(String? sub, String? username);
  Future<bool> getForceLogin();
  Future<void> setForceLogin(bool value);
}

class _ConfigAuthPrefs implements AuthPrefs {
  @override
  Future<({String sub, String username})?> getAccount() =>
      PrefsService.getAuthAccount();

  @override
  Future<void> setAccount(String? sub, String? username) =>
      PrefsService.setAuthAccount(sub, username);

  @override
  Future<bool> getForceLogin() => PrefsService.getAuthForceLogin();

  @override
  Future<void> setForceLogin(bool value) =>
      PrefsService.setAuthForceLogin(value);
}

class _Tokens {
  _Tokens(this.access, this.refresh, this.expiresAt);

  final String access;
  final String refresh;
  final DateTime expiresAt;

  String encode() => jsonEncode({
    'access': access,
    'refresh': refresh,
    'expires_at': expiresAt.millisecondsSinceEpoch,
  });

  static _Tokens? decode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return _Tokens(
        m['access'] as String,
        m['refresh'] as String,
        DateTime.fromMillisecondsSinceEpoch(m['expires_at'] as int),
      );
    } catch (_) {
      return null;
    }
  }
}

/// 析域帳號登入：authorization code + PKCE，loopback redirect（RFC 8252）。
/// 之後的雲端呼叫都從 [accessToken] 取 token。
class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService();

  AuthService({
    http.Client? httpClient,
    AuthTokenStore? tokenStore,
    AuthPrefs? prefs,
    Future<bool> Function(Uri url)? openBrowser,
    DateTime Function()? now,
    this.loginTimeout = const Duration(minutes: 5),
    Random? random,
  }) : _http = httpClient ?? http.Client(),
       _store = tokenStore ?? SecureAuthTokenStore(),
       _prefs = prefs ?? _ConfigAuthPrefs(),
       _openBrowser =
           openBrowser ??
           ((url) => launcher.launchUrl(
             url,
             mode: launcher.LaunchMode.externalApplication,
           )),
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final http.Client _http;
  final AuthTokenStore _store;
  final AuthPrefs _prefs;
  final Future<bool> Function(Uri url) _openBrowser;
  final DateTime Function() _now;
  final Random _random;
  final Duration loginTimeout;

  /// access token 剩餘時間少於這個值就先 refresh
  static const _refreshMargin = Duration(seconds: 60);

  AuthStatus _status = AuthStatus.loggedOut;
  String? _sub;
  String? _username;
  String? _lastError;
  _Tokens? _tokens;
  Completer<Map<String, String>?>? _callback;
  Future<String?>? _refreshing;
  // 進行中的 refresh 是替哪一組 token 送的；登出再登入後不能沿用舊 session 的 refresh
  _Tokens? _refreshingFor;

  AuthStatus get status => _status;
  bool get isLoggedIn => _status == AuthStatus.loggedIn;
  String? get sub => _sub;
  String? get username => _username;

  /// 最近一次登入失敗的原因，供狀態區顯示；下次登入開始時清除
  String? get lastError => _lastError;

  void _setStatus(AuthStatus s) {
    _status = s;
    notifyListeners();
  }

  /// 程式啟動時呼叫：從安全儲存還原登入狀態。任何錯誤都當作未登入
  Future<void> init() async {
    try {
      await _restore();
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  final Completer<void> _ready = Completer<void>();

  /// [init] 結束（還原成功或失敗）後完成；供需要等登入狀態還原的呼叫端使用
  Future<void> get ready => _ready.future;

  Future<void> _restore() async {
    try {
      final tokens = _Tokens.decode(await _store.read());
      final account = await _prefs.getAccount();
      if (tokens == null || account == null) {
        if (tokens != null || account != null) await _clear();
        return;
      }
      _tokens = tokens;
      _sub = account.sub;
      _username = account.username;
      _setStatus(AuthStatus.loggedIn);
    } catch (_) {
      _tokens = null;
      _sub = null;
      _username = null;
      return;
    }
    // access token 已過期時，在背景確認 refresh token 還有效（失效時轉成「需要重新登入」）
    if (_tokens!.expiresAt.isBefore(_now())) {
      unawaited(accessToken());
    }
  }

  /// 取得可用的 access token；快過期時自動 refresh。
  /// refresh token 失效時轉成需要重新登入並回 null；暫時性錯誤（網路、5xx）回 null 但維持登入
  Future<String?> accessToken() {
    final tokens = _tokens;
    if (_status != AuthStatus.loggedIn || tokens == null) {
      return Future.value(null);
    }
    if (tokens.expiresAt.isAfter(_now().add(_refreshMargin))) {
      return Future.value(tokens.access);
    }
    return _startRefresh(tokens);
  }

  /// API 回 401（access token 被拒）時呼叫：強制 refresh 並回傳新的 access token。
  /// [rejected] 是被拒絕的那個 token；若目前的 token 已經不是它（別的呼叫剛 refresh 過），
  /// 直接回傳目前的，不再多送一次 refresh。與 [accessToken] 共用同一個 single-flight。
  /// 未登入回 null；refresh 失敗回 null（refresh token 失效時已轉成需要重新登入）
  Future<String?> refreshAccessToken({String? rejected}) {
    final tokens = _tokens;
    if (_status != AuthStatus.loggedIn || tokens == null) {
      return Future.value(null);
    }
    if (rejected != null && tokens.access != rejected) {
      return Future.value(tokens.access);
    }
    return _startRefresh(tokens);
  }

  /// 伺服器在新 token 下仍回 401（例如帳號被停權）時呼叫：清掉登入資料，轉成需要重新登入
  Future<void> markReloginRequired() async {
    if (_status != AuthStatus.loggedIn) return;
    await _clear();
    _setStatus(AuthStatus.reloginRequired);
  }

  /// 同時間只送一次 refresh：Hydra 會 rotate refresh token，並發會讓其中一個失效
  Future<String?> _startRefresh(_Tokens tokens) {
    final running = _refreshing;
    if (running != null && identical(_refreshingFor, tokens)) return running;
    final f = _refresh(tokens);
    _refreshing = f;
    _refreshingFor = tokens;
    f.whenComplete(() {
      if (!identical(_refreshing, f)) return;
      _refreshing = null;
      _refreshingFor = null;
    }).ignore();
    return f;
  }

  Future<String?> _refresh(_Tokens old) async {
    final http.Response resp;
    try {
      resp = await _http
          .post(
            Uri.parse('$kAuthIssuer/oauth2/token'),
            body: {
              'grant_type': 'refresh_token',
              'refresh_token': old.refresh,
              'client_id': kAuthClientId,
            },
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    // 等待期間已登出或換了 token：結果作廢，不改登入狀態也不寫回 token；
    // 已換發的新 refresh token 順手撤銷，不留下有效的 token
    if (!identical(_tokens, old)) {
      if (resp.statusCode == 200) {
        try {
          final m = jsonDecode(resp.body) as Map<String, dynamic>;
          final refresh = m['refresh_token'];
          if (refresh is String) unawaited(_revoke(refresh));
        } catch (_) {}
      }
      return null;
    }
    if (resp.statusCode == 400 ||
        resp.statusCode == 401 ||
        resp.statusCode == 403) {
      // invalid_grant、access_denied（停權）等：refresh token 不能再用
      await _clear();
      _setStatus(AuthStatus.reloginRequired);
      return null;
    }
    if (resp.statusCode != 200) return null;
    try {
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      final tokens = _parseTokens(m, fallbackRefresh: old.refresh);
      _tokens = tokens;
      await _store.write(tokens.encode());
      return tokens.access;
    } catch (_) {
      return null;
    }
  }

  _Tokens _parseTokens(Map<String, dynamic> m, {String? fallbackRefresh}) {
    final access = m['access_token'] as String;
    final refresh = (m['refresh_token'] as String?) ?? fallbackRefresh;
    if (refresh == null) throw const FormatException('沒有 refresh token');
    final expiresIn = (m['expires_in'] as num?)?.toInt() ?? 3600;
    return _Tokens(access, refresh, _now().add(Duration(seconds: expiresIn)));
  }

  /// 開系統瀏覽器登入。失敗、取消或逾時都回到原本的狀態並設定 [lastError]，不丟例外
  Future<void> login() async {
    if (_status == AuthStatus.loggingIn) return;
    final previous = _status;
    _lastError = null;
    _setStatus(AuthStatus.loggingIn);
    HttpServer? server;
    try {
      final verifier = _randomString(32);
      final state = _randomString(16);
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      final forceLogin = await _prefs.getForceLogin();

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = 'http://127.0.0.1:${server.port}/callback';
      final callback = _callback = Completer<Map<String, String>?>();
      server.listen((req) async {
        if (req.uri.path != '/callback') {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<!doctype html><meta charset="utf-8"><title>osu! Beatmap Viewer</title>'
            '<p>登入流程已完成，可以關閉這個分頁並回到程式。</p>',
          );
        await req.response.close();
        if (!callback.isCompleted) callback.complete(req.uri.queryParameters);
      });

      final authUrl = Uri.parse('$kAuthIssuer/oauth2/auth').replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': kAuthClientId,
          'redirect_uri': redirectUri,
          'scope': kAuthScope,
          'state': state,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          if (forceLogin) 'prompt': 'login',
        },
      );
      if (!await _openBrowser(authUrl)) throw StateError('無法開啟瀏覽器');

      final params = await callback.future.timeout(
        loginTimeout,
        onTimeout: () => throw TimeoutException('登入逾時'),
      );
      if (params == null) {
        // 使用者在程式內取消
        _setStatus(previous);
        return;
      }
      if (params['error'] != null) {
        _lastError = params['error'] == 'access_denied'
            ? '已取消登入'
            : '登入失敗：${params['error']}';
        _setStatus(previous);
        return;
      }
      if (params['state'] != state || params['code'] == null) {
        throw StateError('登入回應不正確');
      }

      final resp = await _http
          .post(
            Uri.parse('$kAuthIssuer/oauth2/token'),
            body: {
              'grant_type': 'authorization_code',
              'code': params['code']!,
              'redirect_uri': redirectUri,
              'client_id': kAuthClientId,
              'code_verifier': verifier,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw StateError('換發 token 失敗（HTTP ${resp.statusCode}）');
      }
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      final tokens = _parseTokens(m);
      final claims = _jwtPayload(m['id_token'] as String);
      final sub = claims['sub'] as String;
      final username = (claims['preferred_username'] as String?) ?? sub;

      await _store.write(tokens.encode());
      await _prefs.setAccount(sub, username);
      await _prefs.setForceLogin(false);
      _tokens = tokens;
      _sub = sub;
      _username = username;
      _setStatus(AuthStatus.loggedIn);
    } on TimeoutException {
      _lastError = '登入逾時，請重試';
      _setStatus(previous);
    } catch (e) {
      _lastError = '登入失敗：$e';
      _setStatus(previous);
    } finally {
      _callback = null;
      await server?.close(force: true);
    }
  }

  /// 取消進行中的登入（例如使用者關掉瀏覽器分頁後按「取消」）
  void cancelLogin() {
    final c = _callback;
    if (c != null && !c.isCompleted) c.complete(null);
  }

  /// 本機登出：撤銷 refresh token、清掉 token 與帳號資訊。不呼叫 Hydra end session，
  /// 以免把瀏覽器裡的析域登入與其他服務一起登出；下一次登入帶 prompt=login 讓使用者可以換帳號
  Future<void> logout() async {
    final tokens = _tokens;
    // 先讓 token 失效，等待撤銷期間回來的 refresh 結果才會被捨棄
    _tokens = null;
    try {
      await _prefs.setForceLogin(true);
    } catch (_) {}
    // 撤銷失敗不擋登出：token 仍會在本機清掉
    if (tokens != null) await _revoke(tokens.refresh);
    await _clear();
    _lastError = null;
    _setStatus(AuthStatus.loggedOut);
  }

  Future<void> _revoke(String refresh) async {
    try {
      await _http
          .post(
            Uri.parse('$kAuthIssuer/oauth2/revoke'),
            body: {
              'token': refresh,
              'token_type_hint': 'refresh_token',
              'client_id': kAuthClientId,
            },
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _clear() async {
    _tokens = null;
    _sub = null;
    _username = null;
    try {
      await _store.delete();
      await _prefs.setAccount(null, null);
    } catch (_) {
      // 儲存層失敗時，記憶體中的狀態仍已清除
    }
  }

  String _randomString(int bytes) => base64Url
      .encode(List.generate(bytes, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  static Map<String, dynamic> _jwtPayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) throw const FormatException('ID token 格式錯誤');
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    return jsonDecode(payload) as Map<String, dynamic>;
  }
}
