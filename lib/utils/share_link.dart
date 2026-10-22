/// 分享連結格式：`osu-storage://share/<token>`（T-07 產生、T-08 解析）
const kShareLinkPrefix = 'osu-storage://share/';

String buildShareLink(String token) =>
    '$kShareLinkPrefix${Uri.encodeComponent(token)}';

/// 從使用者貼上的文字取出 token；格式不符回 null。scheme 不分大小寫，容許前後空白與結尾的 `/`。
String? parseShareLink(String input) {
  final text = input.trim();
  if (text.length < kShareLinkPrefix.length) return null;
  if (text.substring(0, kShareLinkPrefix.length).toLowerCase() !=
      kShareLinkPrefix) {
    return null;
  }
  var rest = text.substring(kShareLinkPrefix.length);
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
