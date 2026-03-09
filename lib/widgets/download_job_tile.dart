import 'package:flutter/material.dart';
import '../models/download_job.dart';
import '../services/download_service.dart';

class DownloadJobTile extends StatelessWidget {
  final DownloadJob job;

  const DownloadJobTile({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    Widget trailingIcon;
    String statusText;
    Color? statusColor;

    switch (job.status) {
      case DownloadStatus.queued:
        trailingIcon = IconButton(
          icon: const Icon(Icons.close, color: Colors.grey),
          tooltip: '取消',
          onPressed: () => DownloadService.instance.cancel(job),
        );
        statusText = '等待中';
        statusColor = null;
      case DownloadStatus.downloading:
        trailingIcon = IconButton(
          icon: const Icon(Icons.stop_circle, color: Colors.orange),
          tooltip: '中止下載',
          onPressed: () => DownloadService.instance.cancel(job),
        );
        statusText = '下載中 ${(job.progress * 100).toStringAsFixed(0)}%';
        statusColor = null;
      case DownloadStatus.done:
        trailingIcon = const Icon(Icons.check_circle, color: Colors.green);
        statusText = '完成';
        statusColor = Colors.green;
      case DownloadStatus.skipped:
        trailingIcon = const Icon(
          Icons.check_circle_outline,
          color: Colors.blue,
        );
        statusText = '已存在，略過';
        statusColor = Colors.blue;
      case DownloadStatus.cancelled:
        trailingIcon = IconButton(
          icon: const Icon(Icons.restart_alt, color: Colors.orange),
          tooltip: '重新加入',
          onPressed: () => DownloadService.instance.retry(job),
        );
        statusText = '已取消';
        statusColor = Colors.orange;
      case DownloadStatus.failed:
        trailingIcon = IconButton(
          icon: const Icon(Icons.refresh, color: Colors.red),
          tooltip: '重試',
          onPressed: () => DownloadService.instance.retry(job),
        );
        statusText = '失敗';
        statusColor = Colors.red;
    }

    return Column(
      children: [
        ListTile(
          title: Text(
            job.title.isNotEmpty ? job.title : 'ID: ${job.onlineID}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ID: ${job.onlineID}  ·  $statusText',
                style: TextStyle(color: statusColor),
              ),
              if (job.error != null)
                Text(
                  job.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          trailing: trailingIcon,
        ),
        if (job.status == DownloadStatus.downloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(
              value: job.progress > 0 ? job.progress : null,
            ),
          ),
      ],
    );
  }
}
