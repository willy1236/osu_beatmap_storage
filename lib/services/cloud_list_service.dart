import 'dart:async';
import 'dart:convert';

import '../models/cloud_entry.dart';
import 'api_client.dart';
import 'cloud_presence_service.dart';
import 'cloud_sync_service.dart' show CloudSyncStatus;

/// 讀取雲端清單的結果。[status] 沿用 [CloudSyncStatus] 的語意
/// （success、rateLimited、unauthorized、unavailable、failed）。
class CloudListResult {
  const CloudListResult(
    this.status, {
    this.entries = const [],
    this.ownerUsername,
    this.ownerAccountId,
    this.message,
  });

  final CloudSyncStatus status;
  final List<CloudEntry> entries;

  /// 別人的分享清單才有（T-08 使用）；自己的清單為 null
  final String? ownerUsername;

  /// 別人的分享清單的擁有者 account_id；後端尚未提供時為 null
  final String? ownerAccountId;
  final String? message;

  bool get ok => status == CloudSyncStatus.success;
}

/// 刪除的結果；[status] 沿用 [CloudSyncStatus]，[deleted] 是後端回報實際刪除的筆數
class CloudDeleteResult {
  const CloudDeleteResult(this.status, {this.deleted = 0, this.message});

  final CloudSyncStatus status;
  final int deleted;
  final String? message;

  bool get ok => status == CloudSyncStatus.success;
}

/// 讀取與刪除自己的雲端清單。HTTP 一律走 [ApiClient]。
/// 不丟例外，結果看 [CloudListResult.status]。
class CloudListService {
  CloudListService({ApiClient? api, void Function()? onChanged})
    : _api = api ?? ApiClient.instance,
      _onChanged = onChanged ?? (() => CloudPresenceService.instance.refresh());

  static final CloudListService instance = CloudListService();

  final ApiClient _api;

  /// 刪除成功後呼叫（預設重讀「已在雲端」標示）；放在 service 裡，刪除途中離開頁面也不會漏
  final void Function() _onChanged;

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

  /// `POST /osu/beatmaps/delete`：刪掉指定的 OnlineID（不存在的不算錯誤）
  Future<CloudDeleteResult> deleteSome(List<int> onlineIds) =>
      _delete('POST', '/osu/beatmaps/delete', {'online_ids': onlineIds});

  /// `DELETE /osu/beatmaps`：清空整份清單
  Future<CloudDeleteResult> clearAll() => _delete('DELETE', '/osu/beatmaps');

  Future<CloudDeleteResult> _delete(
    String method,
    String path, [
    Object? body,
  ]) async {
    try {
      final resp = await _api.send(method, path, jsonBody: body);
      if (resp.statusCode != 200) {
        final e = _errorResult(resp.statusCode);
        final msg = e.status == CloudSyncStatus.failed
            ? '刪除失敗（HTTP ${resp.statusCode}）'
            : e.message;
        return CloudDeleteResult(e.status, message: msg);
      }
      // 後端已刪除，不論回應能否解析都要更新標示
      _onChanged();
      try {
        final json =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        return CloudDeleteResult(
          CloudSyncStatus.success,
          deleted: json['deleted'] as int,
        );
      } catch (_) {
        return const CloudDeleteResult(
          CloudSyncStatus.failed,
          message: '刪除失敗：伺服器回應格式錯誤',
        );
      }
    } on NotSignedInException catch (e) {
      return CloudDeleteResult(CloudSyncStatus.unauthorized, message: '$e');
    } on TimeoutException {
      return const CloudDeleteResult(
        CloudSyncStatus.failed,
        message: '刪除失敗：連線逾時',
      );
    } catch (e) {
      return CloudDeleteResult(CloudSyncStatus.failed, message: '刪除失敗：$e');
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
