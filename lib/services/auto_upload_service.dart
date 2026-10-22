import 'package:flutter/foundation.dart';

import '../models/cloud_entry.dart';
import 'auth_service.dart';
import 'cloud_sync_service.dart';
import 'prefs_service.dart';

/// 自動上傳：開關狀態與「程式開啟時上傳一次」的流程。
///
/// 開關存成 `config.json` 的 `auto_upload_sub`，值等於目前登入的 sub 才算開啟，
/// 所以預設與換帳號後都是關閉；登出時保留，登回同一個域民就恢復開啟。
class AutoUploadService extends ChangeNotifier {
  AutoUploadService({
    AuthService? auth,
    CloudSyncService? sync,
    Future<String?> Function()? readSub,
    Future<void> Function(String? sub)? writeSub,
  }) : _auth = auth ?? AuthService.instance,
       _sync = sync ?? CloudSyncService.instance,
       _readSub = readSub ?? PrefsService.getAutoUploadSub,
       _writeSub = writeSub ?? PrefsService.setAutoUploadSub {
    // 登入、登出或換帳號時，enabled 會跟著變
    _auth.addListener(notifyListeners);
  }

  static final AutoUploadService instance = AutoUploadService();

  final AuthService _auth;
  final CloudSyncService _sync;
  final Future<String?> Function() _readSub;
  final Future<void> Function(String? sub) _writeSub;

  String? _storedSub;
  Future<void>? _loading;

  /// 從設定檔讀入開關狀態（只讀一次）
  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      _storedSub = await _readSub();
    } catch (_) {
      _storedSub = null;
    }
    notifyListeners();
  }

  /// 目前登入的域民是否開啟了自動上傳（未登入一律 false）
  bool get enabled {
    final sub = _auth.sub;
    return _auth.isLoggedIn && sub != null && _storedSub == sub;
  }

  /// 開啟或關閉目前登入域民的自動上傳；未登入時不做事
  Future<void> setEnabled(bool value) async {
    await load();
    final sub = _auth.sub;
    if (!_auth.isLoggedIn || sub == null) return;
    _storedSub = value ? sub : null;
    notifyListeners();
    try {
      await _writeSub(_storedSub);
    } catch (_) {
      // 寫檔失敗時本次執行仍有效，下次開程式會回到舊值
    }
  }

  /// 程式開啟、第一次讀到本機清單後呼叫。
  /// 等登入狀態還原後，若已登入且開啟了自動上傳才上傳；
  /// 未登入、未開啟、被頻率限制擋下都靜默跳過（回傳 null 或對應結果）。
  /// [buildEntries] 在確定要上傳時才呼叫。不會丟例外。
  Future<CloudSyncResult?> runOnStartup(
    List<CloudEntry> Function() buildEntries,
  ) async {
    try {
      await _auth.ready;
      await load();
      if (!enabled) return null;
      return await _sync.upload(buildEntries(), trigger: 'auto');
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    super.dispose();
  }
}
