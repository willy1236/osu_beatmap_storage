import 'dart:async';
import 'dart:convert';

import '../models/cloud_entry.dart';
import 'api_client.dart';
import 'cloud_presence_service.dart';
import 'cloud_sync_service.dart' show CloudSyncStatus;
import 'shared_list_service.dart';

/// 對方未開放瀏覽或已不是好友時的說明（後端兩種情況都回 403 `not_friend`，無從區分）
const kFriendNotBrowsable = '無法瀏覽：對方未開放，或你們已不是好友';

/// 瀏覽、複製好友的雲端清單（`/osu/friends/{account_id}/...`）。
/// 回傳型別與 [SharedListService] 相同，不丟例外。
class FriendBrowseService {
  FriendBrowseService({ApiClient? api, void Function()? onCopied})
    : _api = api ?? ApiClient.instance,
      _onCopied = onCopied ?? (() => CloudPresenceService.instance.refresh());

  static final FriendBrowseService instance = FriendBrowseService();

  final ApiClient _api;
  final void Function() _onCopied;

  static String _path(String id) => '/osu/friends/${Uri.encodeComponent(id)}';

  /// `GET /osu/friends/{id}/beatmaps`。403 時 [SharedListResult.expired] 為 true（重試沒有意義）
  Future<SharedListResult> fetch(String accountId) async {
    try {
      final resp = await _api.send('GET', '${_path(accountId)}/beatmaps');
      if (resp.statusCode == 403) {
        return const SharedListResult(
          CloudSyncStatus.failed,
          message: kFriendNotBrowsable,
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
        final ownerId = ownerMap['account_id'];
        return SharedListResult(
          CloudSyncStatus.success,
          entries: (body['entries'] as List)
              .map((e) => CloudEntry.fromJson(e as Map<String, dynamic>))
              .toList(),
          ownerUsername: ownerMap['username'] as String? ?? '',
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

  /// `POST /osu/friends/{id}/copy`：把好友整份清單併進自己的清單；每分鐘限一次（429）
  Future<SharedCopyResult> copyToMine(String accountId) async {
    final r = await _copy(accountId);
    if (r.ok) _onCopied();
    return r;
  }

  Future<SharedCopyResult> _copy(String accountId) async {
    try {
      final resp = await _api.send('POST', '${_path(accountId)}/copy');
      if (resp.statusCode == 403) {
        return const SharedCopyResult(
          CloudSyncStatus.failed,
          message: kFriendNotBrowsable,
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

  static (CloudSyncStatus, String) _error(int code, String what) =>
      switch (code) {
        429 => (CloudSyncStatus.rateLimited, '請稍後再試'),
        401 => (CloudSyncStatus.unauthorized, '登入已失效，請重新登入'),
        503 => (CloudSyncStatus.unavailable, '服務暫時無法使用，請稍後再試'),
        _ => (CloudSyncStatus.failed, '$what（HTTP $code）'),
      };
}
