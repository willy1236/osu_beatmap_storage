import 'dart:async';
import 'dart:convert';

import 'api_client.dart';
import 'friend_service.dart';

/// 代號查詢的結果：[peer] 與 [error] 恰有一個不為 null
class FriendLookupResult {
  const FriendLookupResult.found(FriendPeer this.peer)
    : error = null,
      notFound = false;

  const FriendLookupResult.failed(String this.error, {this.notFound = false})
    : peer = null;

  final FriendPeer? peer;

  /// 失敗的提示文字
  final String? error;

  /// 查無此人或停權中（後端皆為 404）；連不上、逾時等暫時性失敗為 false
  final bool notFound;
}

/// `GET /social/lookup?username=`：用目前的代號找域民。
///
/// 後端不檢查自己或已是好友；那兩種由呼叫端用 `FriendService.relationOf` 判斷。
/// 404（查無此人、停權）與其他失敗分開，暫時連不上不會被誤報成「找不到」。
class FriendLookup {
  FriendLookup({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<FriendLookupResult> find(String username) async {
    try {
      final resp = await _api.send(
        'GET',
        '/social/lookup',
        query: {'username': username},
      );
      if (resp.statusCode == 200) {
        try {
          final j =
              jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
          return FriendLookupResult.found(FriendPeer.fromJson(j, 'created_at'));
        } catch (_) {
          return const FriendLookupResult.failed('伺服器回應格式錯誤，請稍後再試');
        }
      }
      if (resp.statusCode == 404) {
        return const FriendLookupResult.failed('找不到這位域民', notFound: true);
      }
      if (resp.statusCode == 401) {
        return const FriendLookupResult.failed('登入已失效，請重新登入');
      }
      return const FriendLookupResult.failed('請稍後再試');
    } on NotSignedInException catch (e) {
      return FriendLookupResult.failed('$e');
    } on TimeoutException {
      return const FriendLookupResult.failed('請稍後再試');
    } catch (_) {
      return const FriendLookupResult.failed('請稍後再試');
    }
  }
}
