import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// 偵測 osu!lazer 是否正在執行。
///
/// lazer 與 stable 的執行檔都叫 `osu!.exe`，只看程序名稱分不開，要看執行檔的位置。
abstract interface class LazerDetector {
  Future<bool> isRunning();
}

/// [exePath] 是否為 osu!lazer 的執行檔：
/// - 在 `%LOCALAPPDATA%\osulazer\` 之下（Velopack 預設安裝位置，含根目錄的啟動器與 `current\`），或
/// - 同一個資料夾有 `osu.Game.dll`（自訂安裝位置；stable 的資料夾沒有這個檔）
///
/// osu 資料夾（`PrefsService.getOsuDir`）是資料位置，與安裝位置無關，不能拿來推算。
bool isLazerExe(
  String exePath, {
  String? localAppData,
  bool Function(String path)? fileExists,
}) {
  if (p.basename(exePath).toLowerCase() != 'osu!.exe') return false;
  final base = localAppData ?? Platform.environment['LOCALAPPDATA'];
  if (base != null && base.isNotEmpty) {
    final root = p.join(base, 'osulazer');
    if (p.isWithin(root, exePath) || p.equals(root, p.dirname(exePath))) {
      return true;
    }
  }
  final exists = fileExists ?? (path) => File(path).existsSync();
  return exists(p.join(p.dirname(exePath), 'osu.Game.dll'));
}

/// Windows 版：`EnumProcesses` 列出 PID，對每個程序 `OpenProcess`（只要
/// `PROCESS_QUERY_LIMITED_INFORMATION`，同使用者不需系統管理員）後
/// `QueryFullProcessImageName` 取路徑。一次掃描是毫秒等級，不需要啟動外部程序。
class WindowsLazerDetector implements LazerDetector {
  WindowsLazerDetector({this.localAppData});

  final String? localAppData;

  /// 同一個路徑只判斷一次（判斷會碰檔案系統）
  final Map<String, bool> _cache = {};

  @override
  Future<bool> isRunning() async {
    if (!Platform.isWindows) return false;
    for (final path in _imagePaths()) {
      final lazer = _cache[path] ??= isLazerExe(
        path,
        localAppData: localAppData,
      );
      if (lazer) return true;
    }
    return false;
  }

  /// 名稱為 `osu!.exe` 的程序的完整路徑
  List<String> _imagePaths() {
    final result = <String>[];
    const maxPids = 4096;
    final pids = calloc<Uint32>(maxPids);
    final needed = calloc<Uint32>();
    final buf = calloc<Uint16>(1024);
    final size = calloc<Uint32>();
    try {
      if (EnumProcesses(pids, maxPids * sizeOf<Uint32>(), needed) == 0) {
        return result;
      }
      final count = needed.value ~/ sizeOf<Uint32>();
      for (var i = 0; i < count; i++) {
        final pid = pids[i];
        if (pid == 0) continue;
        final h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (h == 0) continue; // 其他使用者或受保護的程序
        try {
          size.value = 1024;
          if (QueryFullProcessImageName(h, 0, buf.cast<Utf16>(), size) == 0) {
            continue;
          }
          final path = buf.cast<Utf16>().toDartString(length: size.value);
          if (p.basename(path).toLowerCase() == 'osu!.exe') {
            result.add(path);
          }
        } finally {
          CloseHandle(h);
        }
      }
      return result;
    } finally {
      calloc.free(pids);
      calloc.free(needed);
      calloc.free(buf);
      calloc.free(size);
    }
  }
}
