import 'package:flutter/material.dart';

import '../services/osu_settings_service.dart';

/// 設定項目「公開我的清單」：好友能否瀏覽我的整份雲端清單（與分享連結互相獨立）
class BrowseSetting extends StatefulWidget {
  const BrowseSetting({super.key, this.service});

  /// 測試用；預設使用 [OsuSettingsService.instance]
  final OsuSettingsService? service;

  @override
  State<BrowseSetting> createState() => _BrowseSettingState();
}

class _BrowseSettingState extends State<BrowseSetting> {
  bool? _value;
  String? _error;
  bool _saving = false;

  OsuSettingsService get _service =>
      widget.service ?? OsuSettingsService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _service.getFriendsCanBrowse();
    if (!mounted) return;
    setState(() {
      _value = v;
      _error = v == null ? '無法讀取設定（需要登入）' : null;
    });
  }

  Future<void> _change(bool v) async {
    setState(() => _saving = true);
    final r = await _service.setFriendsCanBrowse(v);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r == null) {
        _error = '無法更新設定';
      } else {
        _value = r;
        _error = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_value == null && _error != null) {
      return Row(
        children: [
          Expanded(child: Text(_error!)),
          TextButton(onPressed: _load, child: const Text('重試')),
        ],
      );
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('讓好友瀏覽我的雲端清單'),
      subtitle: Text(_error ?? '關閉後所有好友都看不到；不影響分享連結'),
      value: _value ?? false,
      onChanged: _value == null || _saving ? null : _change,
    );
  }
}
