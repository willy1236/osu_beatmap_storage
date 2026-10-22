import 'package:flutter/material.dart';
import 'app.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 不等待：還原登入狀態失敗或較慢都不影響程式啟動
  AuthService.instance.init();
  runApp(const OsuBeatmapApp());
}
