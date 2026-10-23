import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'app.dart';
import 'services/app_link_service.dart';
import 'services/auth_service.dart';
import 'services/auto_upload_service.dart';
import 'services/protocol_registrar.dart';

void main(List<String> args) {
  // 從 osu-storage:// 連結啟動時，工作目錄沿用呼叫端（瀏覽器、Discord）的，
  // 改回執行檔所在資料夾，config.json 與下載資料夾才不會跑掉
  if (args.any(
    (a) => a.toLowerCase().startsWith('${ProtocolRegistrar.scheme}:'),
  )) {
    Directory.current = p.dirname(Platform.resolvedExecutable);
  }
  WidgetsFlutterBinding.ensureInitialized();
  // 不等待：還原登入狀態失敗或較慢都不影響程式啟動
  AuthService.instance.init();
  // 不等待：先讀入自動上傳開關，帳號選單才不會在讀到清單前顯示成關閉
  AutoUploadService.instance.load();
  // 盡早開始接收連結（冷啟動的第一條連結會先暫存到開始監聽）
  AppLinkService.instance.start();
  // 不等待：註冊 osu-storage:// 指向目前的執行檔，失敗不影響程式
  ProtocolRegistrar().registerIfNeeded();
  runApp(const OsuBeatmapApp());
}
