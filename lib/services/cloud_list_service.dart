import 'dart:async';
import 'dart:convert';

import '../models/cloud_entry.dart';
import 'api_client.dart';
import 'cloud_sync_service.dart' show CloudSyncStatus;

/// 讀取雲端清單的結果。[status] 沿用 [CloudSyncStatus] 的語意
/// （success、rateLimited、unauthorized、unavailable、failed）。
class CloudListResult {
  const CloudListResult(
    this.status, {
    this.entries = const [],
    this.ownerUsername,
    this.message,
  });

  final CloudSyncStatus status;
  final List<CloudEntry> entries;

  /// 別人的分享清單才有（T-08 使用）；自己的清單為 null
  final String? ownerUsername;
  final String? message;

  bool get ok => status == CloudSyncStatus.success;
}

/// 讀取（之後 T-04 起也包含刪除）自己的雲端清單。HTTP 一律走 [ApiClient]。
/// 不丟例外，結果看 [CloudListResult.status]。
class CloudListService {
  CloudListService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  static final CloudListService instance = CloudListService();

  final ApiClient _api;

  /// `GET /osu/beatmaps`：自己的整份清單（依 date_added 新到舊）
  Future<CloudListResult> fetchMine() async {
    try {
      final resp = await _api.send('GET', '/osu/beatmaps');
      if (resp.statusCode != 200) return _errorResult(resp.statusCode);
      try {
        final body =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final list = (body['entries'] as List)
            .map((e) => CloudEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        return CloudListResult(CloudSyncStatus.success, entries: list);
      } catch (_) {
        return const CloudListResult(
          CloudSyncStatus.failed,
          message: '讀取失敗：伺服器回應格式錯誤',
        );
      }
    } on NotSignedInException catch (e) {
      return CloudListResult(CloudSyncStatus.unauthorized, message: '$e');
    } on TimeoutException {
      return const CloudListResult(
        CloudSyncStatus.failed,
        message: '讀取失敗：連線逾時',
      );
    } catch (e) {
      return CloudListResult(CloudSyncStatus.failed, message: '讀取失敗：$e');
    }
  }

  static CloudListResult _errorResult(int code) => switch (code) {
    429 => const CloudListResult(CloudSyncStatus.rateLimited, message: '請稍後再試'),
    401 => const CloudListResult(
      CloudSyncStatus.unauthorized,
      message: '登入已失效，請重新登入',
    ),
    503 => const CloudListResult(
      CloudSyncStatus.unavailable,
      message: '登入服務暫時無法使用，請稍後再試',
    ),
    _ => CloudListResult(CloudSyncStatus.failed, message: '讀取失敗（HTTP $code）'),
  };
}
