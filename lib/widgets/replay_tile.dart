import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/danser_service.dart';

class ReplayTile extends StatefulWidget {
  final File file;

  const ReplayTile({super.key, required this.file});

  @override
  State<ReplayTile> createState() => _ReplayTileState();
}

class _ReplayTileState extends State<ReplayTile> {
  StreamSubscription<double>? _sub;
  double _progress = 0;
  bool _rendering = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String get _outputPath {
    final dir = p.dirname(widget.file.path);
    final name = p.basenameWithoutExtension(widget.file.path);
    return p.join(dir, '$name.mp4');
  }

  bool get _mp4Exists => File(_outputPath).existsSync();

  void _startRender() {
    if (_rendering) return;
    setState(() {
      _rendering = true;
      _error = null;
      _done = false;
      _progress = 0;
    });
    _sub = DanserService.instance
        .renderReplay(widget.file.path, _outputPath)
        .listen(
          (prog) => setState(() => _progress = prog),
          onDone: () => setState(() {
            _rendering = false;
            _done = true;
            _progress = 1;
          }),
          onError: (Object e) => setState(() {
            _rendering = false;
            _error = e.toString();
          }),
          cancelOnError: true,
        );
  }

  void _cancelRender() {
    _sub?.cancel();
    _sub = null;
    setState(() {
      _rendering = false;
      _progress = 0;
    });
  }

  Future<void> _revealInExplorer() async {
    await Process.run('explorer', ['/select,', _outputPath]);
  }

  @override
  Widget build(BuildContext context) {
    final stat = widget.file.statSync();
    final name = p.basenameWithoutExtension(widget.file.path);
    final sizeKb = (stat.size / 1024).toStringAsFixed(1);
    final modified = _formatDate(stat.modified.toLocal());
    final mp4Exists = _mp4Exists;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.sports_esports,
                    size: 16,
                    color: Colors.pinkAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (mp4Exists && !_rendering)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      icon: const Icon(Icons.folder_open, size: 18),
                      tooltip: '在檔案總管中顯示',
                      onPressed: _revealInExplorer,
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                _buildActionButton(mp4Exists),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule, size: 11, color: Colors.grey[500]),
                const SizedBox(width: 3),
                Text(
                  modified,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const SizedBox(width: 12),
                Icon(Icons.data_usage, size: 11, color: Colors.grey[500]),
                const SizedBox(width: 3),
                Text(
                  '$sizeKb KB',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                if (mp4Exists) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.videocam,
                    size: 11,
                    color: Colors.greenAccent[400],
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '已有 MP4',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.greenAccent[400],
                    ),
                  ),
                ],
              ],
            ),
            if (_rendering || _done || _error != null) ...[
              const SizedBox(height: 8),
              _buildStatusRow(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(bool mp4Exists) {
    if (_rendering) {
      return TextButton.icon(
        onPressed: _cancelRender,
        icon: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('取消'),
        style: TextButton.styleFrom(foregroundColor: Colors.orange),
      );
    }
    final danserReady = DanserService.instance.isReady;
    return FilledButton.tonalIcon(
      onPressed: danserReady ? _startRender : null,
      icon: Icon(
        mp4Exists ? Icons.refresh : Icons.movie_creation_outlined,
        size: 16,
      ),
      label: Text(mp4Exists ? '重新匯出' : '匯出 MP4'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildStatusRow() {
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 14,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 4),
              const Text(
                'danser 錯誤（可滾動）',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: SelectableText(
                _error!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.redAccent,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (_done) {
      return Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 14,
            color: Colors.greenAccent[400],
          ),
          const SizedBox(width: 4),
          Text(
            '匯出完成！',
            style: TextStyle(fontSize: 11, color: Colors.greenAccent[400]),
          ),
        ],
      );
    }
    // 渲染中
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '渲染中... ${(_progress * 100).toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: _progress, minHeight: 4),
        ),
      ],
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
