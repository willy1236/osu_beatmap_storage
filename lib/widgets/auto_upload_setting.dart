import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/auto_upload_service.dart';

/// 設定對話框的「自動上傳」開關：開程式讀到本機清單後，自動把清單上傳到雲端
class AutoUploadSetting extends StatefulWidget {
  const AutoUploadSetting({super.key, this.service, this.auth});

  /// 測試時注入；預設用 [AutoUploadService.instance]
  final AutoUploadService? service;
  final AuthService? auth;

  @override
  State<AutoUploadSetting> createState() => _AutoUploadSettingState();
}

class _AutoUploadSettingState extends State<AutoUploadSetting> {
  bool _loaded = false;

  AutoUploadService get _service =>
      widget.service ?? AutoUploadService.instance;
  AuthService get _auth => widget.auth ?? AuthService.instance;

  @override
  void initState() {
    super.initState();
    _service.load().whenComplete(() {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_service, _auth]),
      builder: (context, _) {
        final canChange = _auth.isLoggedIn && _loaded;
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('開程式時自動上傳我的清單'),
          subtitle: Text(_auth.isLoggedIn ? '上傳到目前登入的域民帳號' : '登入後才能設定'),
          value: _service.enabled,
          onChanged: canChange ? (v) => _service.setEnabled(v) : null,
        );
      },
    );
  }
}
