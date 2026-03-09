import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/prefs_service.dart';
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
    final skinName = await PrefsService.getSkinName();
    final skinsDir = await PrefsService.getSkinsDir();
    if (!context.mounted) return;

    final nameCtrl = TextEditingController(text: skinName);
    final dirCtrl = TextEditingController(text: skinsDir);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skin 設定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skin 名稱',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                hintText: '留空 = 使用 danser 目前設定',
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Skins 資料夾路徑（選填）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: dirCtrl,
              decoration: const InputDecoration(
                hintText:
                    '留空 = 使用 danser/Skins/\n例：C:/Users/你/AppData/Local/osu!/Skins',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '填入 Skin 名稱後，每次渲染都會套用該 skin。\nSkins 資料夾可指向 osu!stable 的 Skins 目錄。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await PrefsService.setSkinName(nameCtrl.text.trim());
              await PrefsService.setSkinsDir(dirCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('儲存'),
          ),
        ],
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
