import 'package:flutter/material.dart';
import '../services/update_service.dart';

/// NavigationRail 底部的更新提示：有新版才出現，點擊開啟更新對話框
class UpdateButton extends StatelessWidget {
  const UpdateButton({super.key});

  @override
  Widget build(BuildContext context) {
    final service = UpdateService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final info = service.available;
        if (info == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '有新版本 v${info.version}',
                icon: const Badge(child: Icon(Icons.system_update_alt)),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _UpdateDialog(),
                ),
              ),
              Text('有新版本', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final service = UpdateService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final info = service.available!;
        final busy =
            service.status == UpdateStatus.downloading ||
            service.status == UpdateStatus.installing;
        return AlertDialog(
          title: Text('更新到 v${info.version}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('目前版本 v${service.currentVersion}'),
                const SizedBox(height: 12),
                if (info.notes.isNotEmpty)
                  Flexible(
                    child: SingleChildScrollView(
                      child: SelectableText(info.notes),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '只會替換程式檔，config.json、下載的圖譜與 danser 都會保留。'
                  '更新時程式會關閉，完成後自動重新開啟。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (busy) ...[
                  const SizedBox(height: 12),
                  Text(
                    service.status == UpdateStatus.downloading
                        ? '下載中…'
                        : '準備安裝…',
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: service.progress),
                ],
                if (service.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    service.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('稍後'),
            ),
            FilledButton(
              onPressed: busy ? null : service.install,
              child: Text(
                service.status == UpdateStatus.failed ? '重試' : '更新並重新啟動',
              ),
            ),
          ],
        );
      },
    );
  }
}
