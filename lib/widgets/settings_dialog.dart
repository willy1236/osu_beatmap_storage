import 'package:flutter/material.dart';
import '../services/autostart_service.dart';
import '../services/prefs_service.dart';
import '../services/tray_service.dart';

/// 設定對話框的一個項目。新增設定（例如 T-06 的「公開我的清單」、T-10 的「顯示遊玩狀態」）：
/// 寫一個 widget，在 [defaultSettingsEntries] 標示「新項目插入處」的位置加一個 [SettingsEntry]。
class SettingsEntry {
  const SettingsEntry({required this.title, required this.builder});

  /// 項目的標題，顯示在內容上方
  final String title;
  final WidgetBuilder builder;
}

/// 設定對話框預設的項目清單，由上而下排列
final List<SettingsEntry> defaultSettingsEntries = [
  SettingsEntry(title: '關閉視窗時', builder: (_) => const CloseActionSetting()),
  SettingsEntry(title: '開機', builder: (_) => const AutostartSetting()),
  // —— 新項目插入處 ——
];

Future<void> showSettingsDialog(
  BuildContext context, {
  List<SettingsEntry>? entries,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(entries: entries ?? defaultSettingsEntries),
  );
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key, required this.entries});

  final List<SettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    return AlertDialog(
      title: const Text('設定'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                Text(entries[i].title, style: titleStyle),
                const SizedBox(height: 4),
                entries[i].builder(context),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

/// 關閉行為：每次詢問／縮到系統匣／結束程式
class CloseActionSetting extends StatefulWidget {
  const CloseActionSetting({super.key, this.load, this.save});

  /// 測試時注入；預設讀寫 [PrefsService]
  final Future<CloseAction> Function()? load;
  final Future<void> Function(CloseAction)? save;

  @override
  State<CloseActionSetting> createState() => _CloseActionSettingState();
}

class _CloseActionSettingState extends State<CloseActionSetting> {
  CloseAction? _value;

  @override
  void initState() {
    super.initState();
    final load =
        widget.load ??
        () async => CloseAction.parse(await PrefsService.getCloseAction());
    load().then((v) {
      if (mounted) setState(() => _value = v);
    });
  }

  Future<void> _change(CloseAction? v) async {
    if (v == null) return;
    setState(() => _value = v);
    await (widget.save ?? (a) => PrefsService.setCloseAction(a.name))(v);
  }

  static const _labels = {
    CloseAction.ask: '每次詢問',
    CloseAction.tray: '縮到系統匣',
    CloseAction.exit: '結束程式',
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButton<CloseAction>(
      isExpanded: true,
      value: _value,
      onChanged: _value == null ? null : _change,
      items: [
        for (final a in CloseAction.values)
          DropdownMenuItem(value: a, child: Text(_labels[a]!)),
      ],
    );
  }
}

/// 開機自動啟動開關
class AutostartSetting extends StatefulWidget {
  const AutostartSetting({super.key, this.service});

  /// 測試時注入；預設用 [AutostartService.instance]
  final AutostartService? service;

  @override
  State<AutostartSetting> createState() => _AutostartSettingState();
}

class _AutostartSettingState extends State<AutostartSetting> {
  bool? _value;
  String? _error;

  AutostartService get _service => widget.service ?? AutostartService.instance;

  @override
  void initState() {
    super.initState();
    _service.isEnabled().then((v) {
      if (mounted) setState(() => _value = v);
    });
  }

  Future<void> _change(bool v) async {
    try {
      await _service.setEnabled(v);
      if (mounted) {
        setState(() {
          _value = v;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '無法更新開機啟動設定');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('開機時自動啟動'),
      subtitle: Text(_error ?? '開機後直接縮在系統匣，不開視窗'),
      value: _value ?? false,
      onChanged: _value == null ? null : _change,
    );
  }
}
