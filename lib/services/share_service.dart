import 'dart:async';
import 'dart:convert';

import 'api_client.dart';

enum ShareStatus {
  /// 成功（[ShareResult.token] 在 fetch／regenerate 時有值；revoke 為 null）
  ok,

  /// 目前沒有分享連結（GET 404）
  none,

  /// 未登入或登入已失效
  unauthorized,

  /// 其他失敗（網路、逾時、503、5xx、回應格式錯誤）
  failed,
}

class ShareResult {
  const ShareResult(this.status, {this.token, this.message});
  final ShareStatus status;
  final String? token;
  final String? message;
  bool get ok => status == ShareStatus.ok;
}

/// 自己的分享連結（`/osu/share`）。每個域民最多一條；不丟例外，結果看回傳值。
class ShareService {
  ShareService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  static final ShareService instance = ShareService();

  final ApiClient _api;

  /// 查看目前連結；沒有時回 [ShareStatus.none]
  Future<ShareResult> fetch() => _call('GET');

  /// 產生連結；已有時換新 token，舊連結立刻失效
  Future<ShareResult> regenerate() => _call('POST');

  /// 撤銷；沒有連結也算成功
  Future<ShareResult> revoke() => _call('DELETE');

  Future<ShareResult> _call(String method) async {
    try {
      final resp = await _api.send(method, '/osu/share');
      switch (resp.statusCode) {
        case 200:
          final body =
              jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
          final token = body['token'];
          if (token is! String || token.isEmpty) throw const FormatException();
          return ShareResult(ShareStatus.ok, token: token);
        case 204:
          return const ShareResult(ShareStatus.ok);
        case 404:
          return method == 'GET'
              ? const ShareResult(ShareStatus.none)
              : _failed(resp.statusCode);
        case 401:
          return const ShareResult(
            ShareStatus.unauthorized,
            message: '登入已失效，請重新登入',
          );
        case 503:
          return const ShareResult(
            ShareStatus.failed,
            message: '登入服務暫時無法使用，請稍後再試',
          );
        default:
          return _failed(resp.statusCode);
      }
    } on NotSignedInException {
      return const ShareResult(
        ShareStatus.unauthorized,
        message: '未登入或登入已失效，請重新登入',
      );
    } on TimeoutException {
      return const ShareResult(ShareStatus.failed, message: '連線逾時');
    } on FormatException {
      return const ShareResult(ShareStatus.failed, message: '伺服器回應格式錯誤');
    } catch (e) {
      return ShareResult(ShareStatus.failed, message: '連線失敗：$e');
    }
  }

  ShareResult _failed(int code) =>
      ShareResult(ShareStatus.failed, message: '操作失敗（$code）');
}
