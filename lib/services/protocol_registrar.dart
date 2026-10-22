import 'dart:io';

/// 執行 `reg.exe` 的函式；測試時注入假的，避免寫入真實登錄檔
typedef RegRunner = Future<ProcessResult> Function(List<String> args);

Future<ProcessResult> _runReg(List<String> args) => Process.run('reg', args);

/// 把 `osu-storage://` 註冊到目前使用者（`HKCU\Software\Classes\osu-storage`），
/// 指向目前執行檔。不需要系統管理員；還原指令見 [unregisterCommand]。
///
/// 每次啟動先 `reg query` 比對現有的 command，相同就不寫，所以搬移資料夾後下次啟動會自動更新。
class ProtocolRegistrar {
  ProtocolRegistrar({RegRunner? run, String? exePath, bool? isWindows})
    : _run = run ?? _runReg,
      _exe = exePath ?? Platform.resolvedExecutable,
      _isWindows = isWindows ?? Platform.isWindows;

  static const scheme = 'osu-storage';
  static const rootKey = r'HKCU\Software\Classes\osu-storage';
  static const commandKey =
      r'HKCU\Software\Classes\osu-storage\shell\open\command';

  /// 手動還原用
  static const unregisterCommand =
      r'reg delete "HKCU\Software\Classes\osu-storage" /f';

  final RegRunner _run;
  final String _exe;
  final bool _isWindows;

  /// 開啟連結時執行的命令列：`"<exe>" "%1"`
  String get command => '"$_exe" "%1"';

  /// 需要時寫入登錄檔。回傳 true 表示有寫入；已是最新、非 Windows 或失敗都回 false。不丟例外。
  Future<bool> registerIfNeeded() async {
    if (!_isWindows) return false;
    try {
      if (await _isCurrent()) return false;
      final steps = <List<String>>[
        ['add', rootKey, '/ve', '/d', 'URL:$scheme', '/f'],
        ['add', rootKey, '/v', 'URL Protocol', '/d', '', '/f'],
        ['add', commandKey, '/ve', '/d', command, '/f'],
      ];
      for (final args in steps) {
        final r = await _run(args);
        if (r.exitCode != 0) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isCurrent() async {
    final r = await _run(['query', commandKey, '/ve']);
    if (r.exitCode != 0) return false;
    return '${r.stdout}'.toLowerCase().contains(command.toLowerCase());
  }
}
