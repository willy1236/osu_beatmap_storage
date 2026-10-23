import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

/// Windows toast 通知的底層操作；[NotificationService] 只透過它發通知，測試時換成假的
abstract class ToastPlatform {
  /// 跳一則通知；使用者點擊時呼叫 [onClick]
  Future<void> show({
    required String title,
    required String body,
    required VoidCallback onClick,
  });
}

/// 以 local_notifier 實作的 [ToastPlatform]；第一次發通知時才 `setup`，失敗只記 log
class LocalNotifierToast implements ToastPlatform {
  static const appName = 'osu! Beatmap Viewer';

  Future<void>? _setup;

  Future<void> _ensureSetup() =>
      _setup ??= localNotifier.setup(appName: appName);

  @override
  Future<void> show({
    required String title,
    required String body,
    required VoidCallback onClick,
  }) async {
    if (!Platform.isWindows) return;
    try {
      await _ensureSetup();
      final n = LocalNotification(title: title, body: body);
      n.onClick = () {
        onClick();
        localNotifier.destroy(n);
      };
      n.onClose = (_) => localNotifier.destroy(n);
      await n.show();
    } catch (e) {
      // 通知失敗（例如系統關閉通知）不影響其他功能；setup 失敗時下次再試
      _setup = null;
      debugPrint('Windows 通知失敗：$e');
    }
  }
}
