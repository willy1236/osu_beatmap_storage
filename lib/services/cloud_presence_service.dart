import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'cloud_list_service.dart';
import 'cloud_sync_service.dart';

/// 雲端清單上有哪些 OnlineID（供圖譜查看頁標示「已在雲端」）。
///
/// - 登入後自動讀取，登出或換帳號時清掉
/// - 上傳（手動、自動、CSV）成功後自動重讀
/// - 其他會改變雲端清單的動作（刪除、複製別人的清單）由呼叫端呼叫 [refresh]
/// - 讀取失敗時保留上一次的結果
class CloudPresenceService extends ChangeNotifier {
  CloudPresenceService({
    AuthService? auth,
    CloudSyncService? sync,
    Future<CloudListResult> Function()? fetch,
  }) : _auth = auth ?? AuthService.instance,
       _sync = sync ?? CloudSyncService.instance,
       _fetch = fetch ?? CloudListService.instance.fetchMine {
    _auth.addListener(_onAuthChanged);
    _sync.addListener(_onSyncChanged);
    _onAuthChanged();
  }

  static final CloudPresenceService instance = CloudPresenceService();

  final AuthService _auth;
  final CloudSyncService _sync;
  final Future<CloudListResult> Function() _fetch;

  Set<int>? _ids;
  String? _sub;
  bool _wasUploading = false;
  Future<void>? _running;
  bool _again = false;

  /// 已讀到目前登入域民的雲端清單；未登入或還沒讀到時為 false
  bool get loaded => _ids != null;

  /// 這個 OnlineID 是否在雲端清單上（未載入時一律 false）
  bool contains(int onlineId) => _ids?.contains(onlineId) ?? false;

  /// 重新讀取雲端清單；讀取中再次呼叫時，等這次結束後再讀一次
  Future<void> refresh() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _load().whenComplete(() => _running = null);
  }

  Future<void> _load() async {
    do {
      _again = false;
      if (!_auth.isLoggedIn) return;
      final sub = _auth.sub;
      final r = await _fetch();
      // 讀取期間登出或換了帳號：結果不屬於目前的域民
      if (!_auth.isLoggedIn || _auth.sub != sub) return;
      if (r.ok) {
        _ids = {for (final e in r.entries) e.onlineId};
        notifyListeners();
      }
    } while (_again);
  }

  void _onAuthChanged() {
    final sub = _auth.isLoggedIn ? _auth.sub : null;
    if (sub == _sub) return;
    _sub = sub;
    if (_ids != null) {
      _ids = null;
      notifyListeners();
    }
    if (sub != null) refresh();
  }

  void _onSyncChanged() {
    final uploading = _sync.uploading;
    final finished = _wasUploading && !uploading;
    _wasUploading = uploading;
    if (finished && _sync.lastResult?.ok == true) refresh();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _sync.removeListener(_onSyncChanged);
    super.dispose();
  }
}
