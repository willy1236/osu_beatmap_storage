import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants.dart';
import 'auth_service.dart';

/// 沒有可用的登入（未登入、或 refresh token 已失效），請求沒有送出
class NotSignedInException implements Exception {
  const NotSignedInException();
  @override
  String toString() => '未登入或登入已失效，請重新登入';
}

/// 呼叫 domalyze-api 的共用入口：自動帶 `Authorization: Bearer <析域 access token>`，
/// 收到 401 時 refresh token 後重送一次；新 token 仍 401 就把帳號轉成「需要重新登入」。
///
/// 用法（雲端相關的卡都走這裡）：
/// ```dart
/// final resp = await ApiClient.instance.send(
///   'POST', '/osu/beatmaps/delete', jsonBody: {'online_ids': ids});
/// ```
/// - 回傳 [http.Response]，任何狀態碼都原樣回傳（含 429、503、仍然是 401），由呼叫端解讀。
/// - 沒有可用登入時丟 [NotSignedInException]；網路錯誤與逾時（[TimeoutException]）也會丟出，
///   呼叫端自行 catch。
/// - 回應 body 用 `utf8.decode(resp.bodyBytes)` 解碼。
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
    Future<String?> Function(String rejected)? refreshToken,
    Future<void> Function()? onUnauthorized,
    String? baseUrl,
    Duration? timeout,
  }) : _http = httpClient ?? http.Client(),
       _token = tokenProvider ?? (() => AuthService.instance.accessToken()),
       _refresh =
           refreshToken ??
           ((rejected) =>
               AuthService.instance.refreshAccessToken(rejected: rejected)),
       _onUnauthorized =
           onUnauthorized ?? (() => AuthService.instance.markReloginRequired()),
       _baseUrl = baseUrl ?? kApiBase,
       _timeout = timeout ?? const Duration(seconds: 60);

  static final ApiClient instance = ApiClient();

  final http.Client _http;
  final Future<String?> Function() _token;
  final Future<String?> Function(String rejected) _refresh;
  final Future<void> Function() _onUnauthorized;
  final String _baseUrl;
  final Duration _timeout;

  /// 送出請求。[path] 以 `/` 開頭（例如 `/osu/beatmaps`），[jsonBody] 會編成 UTF-8 JSON。
  Future<http.Response> send(
    String method,
    String path, {
    Object? jsonBody,
    Map<String, String>? query,
  }) async {
    final token = await _token();
    if (token == null) throw const NotSignedInException();

    final first = await _once(method, path, jsonBody, query, token);
    if (first.statusCode != 401) return first;

    // token 被拒：強制 refresh。refresh 失敗（暫時性錯誤或已轉成需要重新登入）就把 401 交給呼叫端
    final fresh = await _refresh(token);
    if (fresh == null) return first;

    final second = await _once(method, path, jsonBody, query, fresh);
    if (second.statusCode == 401) await _onUnauthorized();
    return second;
  }

  Future<http.Response> _once(
    String method,
    String path,
    Object? jsonBody,
    Map<String, String>? query,
    String token,
  ) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final req = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (jsonBody != null) {
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.bodyBytes = utf8.encode(jsonEncode(jsonBody));
    }
    return (() async => http.Response.fromStream(await _http.send(req)))()
        .timeout(_timeout);
  }
}
