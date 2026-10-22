import 'package:flutter/material.dart';
import 'app.dart';
import 'services/app_link_service.dart';
import 'services/auth_service.dart';
import 'services/protocol_registrar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 不等待：還原登入狀態失敗或較慢都不影響程式啟動
  AuthService.instance.init();
  // 盡早開始接收連結（冷啟動的第一條連結會先暫存到開始監聽）
  AppLinkService.instance.start();
  // 不等待：註冊 osu-storage:// 指向目前的執行檔，失敗不影響程式
  ProtocolRegistrar().registerIfNeeded();
  runApp(const OsuBeatmapApp());
}
