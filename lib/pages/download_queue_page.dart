import 'dart:io';
import 'package:flutter/material.dart';
import '../models/download_job.dart';
import '../services/download_service.dart';
import '../widgets/download_job_tile.dart';

class DownloadQueuePage extends StatelessWidget {
  const DownloadQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下載佇列'),
        actions: [
          ListenableBuilder(
            listenable: DownloadService.instance,
            builder: (_, _) {
              final hasActive = DownloadService.instance.jobs.any(
                (j) =>
                    j.status == DownloadStatus.queued ||
                    j.status == DownloadStatus.downloading,
              );
              if (!hasActive) return const SizedBox.shrink();
              return TextButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('取消全部'),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () => DownloadService.instance.cancelAll(),
              );
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('開啟資料夾'),
            onPressed: () async {
              final path = '${Directory.current.path}\\osu_downloads';
              await Directory(path).create(recursive: true);
              await Process.run('explorer', [path]);
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: DownloadService.instance,
        builder: (_, _) {
          final jobs = DownloadService.instance.jobs;
          if (jobs.isEmpty) {
            return const Center(child: Text('佇列為空，請點擊圖譜旁的下載按鈕加入'));
          }
          final reversed = jobs.reversed.toList();
          return ListView.builder(
            itemCount: reversed.length,
            itemBuilder: (_, i) => DownloadJobTile(job: reversed[i]),
          );
        },
      ),
    );
  }
}
