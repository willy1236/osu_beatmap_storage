import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'app.dart';
import 'services/app_link_service.dart';
import 'services/auth_service.dart';
import 'services/autostart_service.dart';
import 'services/auto_upload_service.dart';
import 'services/cloud_presence_service.dart';
import 'services/protocol_registrar.dart';
import 'services/tray_service.dart';
import 'services/update_service.dart';
import 'widgets/close_action_dialog.dart';

Future<void> main(List<String> args) async {
  // 從 osu-storage:// 連結或開機自動啟動時，工作目錄不是執行檔所在資料夾
  // （前者沿用呼叫端的，後者是 System32），改回來 config.json 與下載資料夾才不會跑掉
  final autostart = args.contains(autostartArg);
  if (autostart ||
      args.any(
        (a) => a.toLowerCase().startsWith('${ProtocolRegistrar.scheme}:'),
      )) {
    Directory.current = p.dirname(Platform.resolvedExecutable);
  }
  WidgetsFlutterBinding.ensureInitialized();
  // 攔截關閉視窗；開機自動啟動時視窗尚未顯示（見 flutter_window.cpp），直接縮在系統匣
  TrayService.askHook = () {
    final context = appNavigatorKey.currentState?.overlay?.context;
    return context == null ? Future.value() : showCloseActionDialog(context);
  };
  await TrayService.instance.init();
  if (autostart) await TrayService.instance.hideToTray();
  // 不等待：還原登入狀態失敗或較慢都不影響程式啟動
  AuthService.instance.init();
  // 不等待：先讀入自動上傳開關，帳號選單才不會在讀到清單前顯示成關閉
  AutoUploadService.instance.load();
  // 盡早建立：登入還原後自動讀取雲端清單，供圖譜查看頁標示「已在雲端」
  CloudPresenceService.instance;
  // 盡早開始接收連結（冷啟動的第一條連結會先暫存到開始監聽）
  AppLinkService.instance.start();
  // 不等待：註冊 osu-storage:// 指向目前的執行檔，失敗不影響程式
  ProtocolRegistrar().registerIfNeeded();
  // 不等待：查 GitHub 有沒有新版，有才在側欄顯示更新提示
  UpdateService.instance.check();
  // 不等待：開機啟動已開啟時，讓 Run 項目對齊目前的執行檔路徑
  AutostartService.instance.syncOnStart();
  runApp(const OsuBeatmapApp());
}
