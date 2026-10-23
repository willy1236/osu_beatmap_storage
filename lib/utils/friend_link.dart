/// 好友邀請連結格式：`osu-storage://friend/<token>`（與分享連結共用 scheme）
const kFriendLinkPrefix = 'osu-storage://friend/';

String buildFriendLink(String token) =>
    '$kFriendLinkPrefix${Uri.encodeComponent(token)}';

/// 從使用者貼上的文字取出 token；格式不符回 null。規則同 `parseShareLink`：
/// scheme 不分大小寫，容許前後空白與結尾的 `/`。
String? parseFriendLink(String input) {
  final text = input.trim();
  if (text.length < kFriendLinkPrefix.length) return null;
  if (text.substring(0, kFriendLinkPrefix.length).toLowerCase() !=
      kFriendLinkPrefix) {
    return null;
  }
  var rest = text.substring(kFriendLinkPrefix.length);
  while (rest.endsWith('/')) {
    rest = rest.substring(0, rest.length - 1);
  }
  if (rest.isEmpty || rest.contains(RegExp(r'[/?#\s]'))) return null;
  try {
    final token = Uri.decodeComponent(rest);
    return token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}
