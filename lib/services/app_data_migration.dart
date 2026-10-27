import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把舊版放在 `%APPDATA%\com.example\osu_beatmap_storage` 的資料搬到現在的位置。
///
/// path_provider 以 exe 版本資訊的 CompanyName、ProductName 組出資料夾，舊版是 Flutter 預設的
/// `com.example`。登入資訊（flutter_secure_storage.dat）以 DPAPI 綁定 Windows 使用者、不綁路徑，
/// 搬過去就能繼續用，不必重新登入。
/// 必須在任何用到 path_provider 的服務（如 AuthService）之前呼叫。
Future<void> migrateLegacyAppData() async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null) return;
  await moveAppData(
    from: Directory(p.join(appData, 'com.example', 'osu_beatmap_storage')),
    to: await getApplicationSupportDirectory(),
  );
}

/// 把 [from] 的內容複製進 [to]，已存在的檔案不覆蓋；全部成功才刪掉 [from]，
/// 上層資料夾空了一併刪除。失敗靜默略過，舊資料保留到下次啟動再試
Future<void> moveAppData({
  required Directory from,
  required Directory to,
}) async {
  try {
    if (!await from.exists() || p.equals(from.path, to.path)) return;
    await _copyMissing(from, to);
    await from.delete(recursive: true);
    final parent = from.parent;
    if (await parent.list().isEmpty) await parent.delete();
  } catch (_) {}
}

Future<void> _copyMissing(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list(followLinks: false)) {
    final dest = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyMissing(entity, Directory(dest));
    } else if (entity is File && !await File(dest).exists()) {
      await entity.copy(dest);
    }
  }
}
