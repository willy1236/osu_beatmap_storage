import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/presence_service.dart';

/// 設定對話框的「上線狀態」開關：是否讓好友看到我正在玩 osu!lazer
class PresenceSetting extends StatefulWidget {
  const PresenceSetting({super.key, this.service, this.auth});

  /// 測試時注入；預設用 [PresenceService.instance]
  final PresenceService? service;
  final AuthService? auth;

  @override
  State<PresenceSetting> createState() => _PresenceSettingState();
}

class _PresenceSettingState extends State<PresenceSetting> {
  String? _error;

  PresenceService get _service => widget.service ?? PresenceService.instance;
  AuthService get _auth => widget.auth ?? AuthService.instance;

  Future<void> _change(bool v) async {
    final ok = await _service.setVisible(v);
    if (mounted) setState(() => _error = ok ? null : '無法更新上線狀態設定');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_service, _auth]),
      builder: (context, _) {
        final enabled = _auth.isLoggedIn && _service.visibleLoaded;
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('讓好友看到我正在遊玩'),
          subtitle: Text(
            _error ?? (_auth.isLoggedIn ? '只顯示「遊玩中」，不會顯示正在玩哪張圖' : '登入後才能設定'),
          ),
          value: _service.visible,
          onChanged: enabled ? _change : null,
        );
      },
    );
  }
}
