import 'dart:convert';

import 'api_client.dart';

/// 自己的 osu 設定（`/osu/settings`），目前只有「好友能否瀏覽我的清單」。
/// 設定存在後端，不進 `config.json`。失敗時回 null，不丟例外。
class OsuSettingsService {
  OsuSettingsService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  static final OsuSettingsService instance = OsuSettingsService();

  final ApiClient _api;

  /// `GET /osu/settings`
  Future<bool?> getFriendsCanBrowse() => _call('GET', null);

  /// `PUT /osu/settings`；回傳後端確認的值
  Future<bool?> setFriendsCanBrowse(bool value) => _call('PUT', value);

  Future<bool?> _call(String method, bool? value) async {
    try {
      final resp = await _api.send(
        method,
        '/osu/settings',
        jsonBody: value == null ? null : {'friends_can_browse': value},
      );
      if (resp.statusCode != 200) return null;
      final body =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      return body['friends_can_browse'] as bool;
    } catch (_) {
      return null;
    }
  }
}
