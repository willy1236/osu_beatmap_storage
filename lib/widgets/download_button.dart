import 'package:flutter/material.dart';
import '../models/download_job.dart';
import '../services/download_service.dart';

class DownloadButton extends StatelessWidget {
  final int onlineID;
  final String title;

  const DownloadButton({
    super.key,
    required this.onlineID,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    if (onlineID <= 0) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: DownloadService.instance,
      builder: (_, _) {
        final job = DownloadService.instance.jobFor(onlineID);
        if (job == null) {
          return IconButton(
            icon: const Icon(Icons.download, size: 20),
            tooltip: '下載 .osz',
            visualDensity: VisualDensity.compact,
            onPressed: () => DownloadService.instance.enqueue(onlineID, title),
          );
        }
        return switch (job.status) {
          DownloadStatus.queued => IconButton(
            icon: const Icon(
              Icons.hourglass_empty,
              size: 20,
              color: Colors.grey,
            ),
            tooltip: '取消',
            visualDensity: VisualDensity.compact,
            onPressed: () => DownloadService.instance.cancel(job),
          ),
          DownloadStatus.downloading => IconButton(
            icon: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: job.progress > 0 ? job.progress : null,
                  ),
                ),
                const Icon(Icons.close, size: 12),
              ],
            ),
            tooltip: '取消下載',
            visualDensity: VisualDensity.compact,
            onPressed: () => DownloadService.instance.cancel(job),
          ),
          DownloadStatus.done => const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.check_circle, size: 20, color: Colors.green),
          ),
          DownloadStatus.skipped => const Tooltip(
            message: '已存在，略過',
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.check_circle_outline,
                size: 20,
                color: Colors.blue,
              ),
            ),
          ),
          DownloadStatus.cancelled => IconButton(
            icon: const Icon(Icons.restart_alt, size: 20, color: Colors.orange),
            tooltip: '已取消，點擊重新加入',
            visualDensity: VisualDensity.compact,
            onPressed: () => DownloadService.instance.retry(job),
          ),
          DownloadStatus.failed => IconButton(
            icon: const Icon(Icons.error, size: 20, color: Colors.red),
            tooltip: '失敗，點擊重試',
            visualDensity: VisualDensity.compact,
            onPressed: () => DownloadService.instance.retry(job),
          ),
        };
      },
    );
  }
}
