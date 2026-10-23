import 'dart:async';
import 'dart:convert';

import '../models/cloud_entry.dart';
import 'api_client.dart';
import 'cloud_list_service.dart' show CloudListResult;
import 'cloud_presence_service.dart';
import 'cloud_sync_service.dart' show CloudSyncStatus;

/// 分享連結無效、已撤銷或已重新產生時的說明
const kSharedLinkExpired = '連結已失效';

/// 讀取別人的分享清單的結果。[expired] 為 true 表示連結失效（後端 404），重試沒有意義。
class SharedListResult extends CloudListResult {
  const SharedListResult(
    super.status, {
    super.entries,
    super.ownerUsername,
    super.ownerAccountId,
    super.message,
    this.expired = false,
  });

  final bool expired;
}

/// 複製別人的清單到自己的雲端清單的結果
class SharedCopyResult {
  const SharedCopyResult(
    this.status, {
    this.inserted = 0,
    this.updated = 0,
    this.message,
  });

  /// 沿用 [CloudSyncStatus] 的語意：success、rateLimited、unauthorized、unavailable、failed
  final CloudSyncStatus status;
  final int inserted;
  final int updated;
  final String? message;

  bool get ok => status == CloudSyncStatus.success;
}

/// 用分享連結讀取、複製別人的清單（`/osu/shared/{token}`）。HTTP 一律走 [ApiClient]，
/// 不丟例外，結果看回傳值的 status。
class SharedListService {
  SharedListService({ApiClient? api, void Function()? onCopied})
    : _api = api ?? ApiClient.instance,
      _onCopied = onCopied ?? (() => CloudPresenceService.instance.refresh());

  static final SharedListService instance = SharedListService();

  final ApiClient _api;

  /// 複製成功後呼叫（預設重讀「已在雲端」標示）；放在 service 裡，關掉頁面也不會漏
  final void Function() _onCopied;

  /// `GET /osu/shared/{token}`：擁有者目前的代號與整份清單
  Future<SharedListResult> fetch(String token) async {
    try {
      final resp = await _api.send('GET', _path(token));
      if (resp.statusCode == 404) {
        return const SharedListResult(
          CloudSyncStatus.failed,
          message: kSharedLinkExpired,
          expired: true,
        );
      }
      if (resp.statusCode != 200) {
        final e = _error(resp.statusCode, '讀取失敗');
        return SharedListResult(e.$1, message: e.$2);
      }
      try {
        final body =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final ownerMap = body['owner'] as Map<String, dynamic>;
        final owner = ownerMap['username'] as String? ?? '';
        final ownerId = ownerMap['account_id'];
        final entries = (body['entries'] as List)
            .map((e) => CloudEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        return SharedListResult(
          CloudSyncStatus.success,
          entries: entries,
          ownerUsername: owner,
          ownerAccountId: ownerId is String && ownerId.isNotEmpty
              ? ownerId
              : null,
        );
      } catch (_) {
        return const SharedListResult(
          CloudSyncStatus.failed,
          message: '讀取失敗：伺服器回應格式錯誤',
        );
      }
    } on NotSignedInException catch (e) {
      return SharedListResult(CloudSyncStatus.unauthorized, message: '$e');
    } on TimeoutException {
      return const SharedListResult(
        CloudSyncStatus.failed,
        message: '讀取失敗：連線逾時',
      );
    } catch (e) {
      return SharedListResult(CloudSyncStatus.failed, message: '讀取失敗：$e');
    }
  }

  /// `POST /osu/shared/{token}/copy`：把對方整份清單併進自己的清單（對方清單不變）。
  /// 後端每分鐘限一次，被擋時回 [CloudSyncStatus.rateLimited]。
  Future<SharedCopyResult> copyToMine(String token) async {
    final r = await _copy(token);
    if (r.ok) _onCopied();
    return r;
  }

  Future<SharedCopyResult> _copy(String token) async {
    try {
      final resp = await _api.send('POST', '${_path(token)}/copy');
      if (resp.statusCode == 404) {
        return const SharedCopyResult(
          CloudSyncStatus.failed,
          message: kSharedLinkExpired,
        );
      }
      if (resp.statusCode != 200) {
        final e = _error(resp.statusCode, '複製失敗');
        return SharedCopyResult(e.$1, message: e.$2);
      }
      try {
        final body =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        return SharedCopyResult(
          CloudSyncStatus.success,
          inserted: body['inserted'] as int,
          updated: body['updated'] as int,
        );
      } catch (_) {
        return const SharedCopyResult(
          CloudSyncStatus.failed,
          message: '複製失敗：伺服器回應格式錯誤',
        );
      }
    } on NotSignedInException catch (e) {
      return SharedCopyResult(CloudSyncStatus.unauthorized, message: '$e');
    } on TimeoutException {
      return const SharedCopyResult(
        CloudSyncStatus.failed,
        message: '複製失敗：連線逾時',
      );
    } catch (e) {
      return SharedCopyResult(CloudSyncStatus.failed, message: '複製失敗：$e');
    }
  }

  static String _path(String token) =>
      '/osu/shared/${Uri.encodeComponent(token)}';

  static (CloudSyncStatus, String) _error(int code, String what) =>
      switch (code) {
        429 => (CloudSyncStatus.rateLimited, '請稍後再試'),
        401 => (CloudSyncStatus.unauthorized, '登入已失效，請重新登入'),
        503 => (CloudSyncStatus.unavailable, '登入服務暫時無法使用，請稍後再試'),
        _ => (CloudSyncStatus.failed, '$what（HTTP $code）'),
      };
}
