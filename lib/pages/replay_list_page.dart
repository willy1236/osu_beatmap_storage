import 'dart:io';

import 'package:flutter/material.dart';
import 'package:realm/realm.dart' show Realm;
import 'package:path/path.dart' as p;
import '../models/osu_realm_models.dart';
import '../services/prefs_service.dart';
import '../services/realm_service.dart';
import '../widgets/replay_tile.dart';

class ReplayListPage extends StatefulWidget {
  const ReplayListPage({super.key});

  @override
  State<ReplayListPage> createState() => _ReplayListPageState();
}

class _ReplayListPageState extends State<ReplayListPage> {
  List<File> _osrFiles = [];
  bool _loading = false;
  String? _error;
  String? _exportsDir;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final osuDir = await PrefsService.getOsuDir();
      final dir = Directory(p.join(osuDir, 'exports'));
      _exportsDir = dir.path;
      if (!dir.existsSync()) {
        setState(() {
          _loading = false;
          _osrFiles = [];
        });
        return;
      }
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.osr'))
              .toList()
            ..sort(
              (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
            );
      setState(() {
        _loading = false;
        _osrFiles = files;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _showSkinSettings(BuildContext context) async {
    final osuDir = await PrefsService.getOsuDir();
    final realmPath = p.join(osuDir, 'client.realm');

    // 讀取目前已選 skin ID
    final currentId = await PrefsService.getSkinRealmId();
    if (!context.mounted) return;

    // 在 dialog 內部以 StatefulBuilder 管理 loading + 選擇狀態
    await showDialog<void>(
      context: context,
      builder: (ctx) =>
          _SkinPickerDialog(realmPath: realmPath, currentSkinId: currentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回放列表'),
        actions: [
          if (!_loading && _osrFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('${_osrFiles.length} 個回放')),
            ),
          IconButton(
            icon: const Icon(Icons.style_outlined),
            tooltip: 'Skin 設定',
            onPressed: () => _showSkinSettings(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新載入',
            onPressed: _loading ? null : _loadFiles,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                '無法讀取回放目錄',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _error!,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
                onPressed: _loadFiles,
              ),
            ],
          ),
        ),
      );
    }

    if (_osrFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videogame_asset_off, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              _exportsDir != null
                  ? '在 exports/ 目錄中找不到 .osr 回放\n$_exportsDir'
                  : '尚無回放',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _osrFiles.length,
      itemBuilder: (_, i) => ReplayTile(file: _osrFiles[i]),
    );
  }
}

// ── Skin 選擇器 Dialog ────────────────────────────────────────────────────────

class _SkinPickerDialog extends StatefulWidget {
  final String realmPath;
  final String currentSkinId;

  const _SkinPickerDialog({
    required this.realmPath,
    required this.currentSkinId,
  });

  @override
  State<_SkinPickerDialog> createState() => _SkinPickerDialogState();
}

class _SkinPickerDialogState extends State<_SkinPickerDialog> {
  Realm? _realm;
  List<SkinInfo>? _skins;
  String? _error;
  late String _selectedId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentSkinId;
    _loadSkins();
  }

  @override
  void dispose() {
    _realm?.close();
    super.dispose();
  }

  Future<void> _loadSkins() async {
    try {
      final realm = await RealmService.openWithSkins(widget.realmPath);
      _realm = realm;
      final list =
          realm
              .all<SkinInfo>()
              .where((s) => !(s.isProtected)) // 排除內建 skin
              .toList()
            ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
      // 不在這裡關閉 realm，Realm 物件需保持有效直到 dialog 關閉
      if (mounted) setState(() => _skins = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _skins
        ?.where(
          (s) =>
              _query.isEmpty ||
              (s.name ?? '').toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return AlertDialog(
      title: const Text('選擇 Skin'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 400,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜尋...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildList(filtered)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await PrefsService.setSkinRealmId('');
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('不套用 skin'),
        ),
        FilledButton(
          onPressed: _selectedId.isEmpty
              ? null
              : () async {
                  await PrefsService.setSkinRealmId(_selectedId);
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('套用'),
        ),
      ],
    );
  }

  Widget _buildList(List<SkinInfo>? skins) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '讀取失敗：$_error',
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (skins == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (skins.isEmpty) {
      return const Center(
        child: Text('找不到 skin', style: TextStyle(color: Colors.grey)),
      );
    }

    // 頂部加「不使用／沿用 danser 設定」選項
    return ListView.builder(
      itemCount: skins.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          final selected = _selectedId.isEmpty;
          return RadioListTile<String>(
            value: '',
            groupValue: _selectedId,
            dense: true,
            title: const Text(
              '使用 danser 目前 skin',
              style: TextStyle(fontSize: 13),
            ),
            selected: selected,
            onChanged: (v) => setState(() => _selectedId = v ?? ''),
          );
        }
        final skin = skins[i - 1];
        final id = skin.id.toString();
        return RadioListTile<String>(
          value: id,
          groupValue: _selectedId,
          dense: true,
          title: Text(
            skin.name ?? '（未命名）',
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: skin.creator != null && skin.creator!.isNotEmpty
              ? Text(
                  skin.creator!,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onChanged: (v) => setState(() => _selectedId = v ?? ''),
        );
      },
    );
  }
}
