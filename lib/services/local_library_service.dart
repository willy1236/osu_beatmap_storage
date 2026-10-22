import 'package:flutter/foundation.dart';

/// 本機圖譜庫的 OnlineID 集合（供分享清單等頁面標示「本機有／缺」）。
///
/// 由 `BeatmapListPage` 在讀到本機 client.realm 後寫入；尚未讀到（沒有選 realm、讀取失敗）時為 null。
class LocalLibraryService extends ChangeNotifier {
  static final LocalLibraryService instance = LocalLibraryService();

  Set<int>? _onlineIds;

  /// 本機已有的 OnlineID（> 0）；尚未載入時為 null
  Set<int>? get onlineIds => _onlineIds;

  void setOnlineIds(Set<int> ids) {
    _onlineIds = ids;
    notifyListeners();
  }
}
