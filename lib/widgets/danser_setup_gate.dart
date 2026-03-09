import 'package:flutter/material.dart';
import '../services/danser_service.dart';

/// 應用程式啟動閘道：確保 danser-go 已就緒後才顯示主畫面。
///
/// 若執行檔不存在，會顯示「正在準備渲染引擎...」進度畫面並自動下載安裝。
class DanserSetupGate extends StatefulWidget {
  final Widget child;

  const DanserSetupGate({super.key, required this.child});

  @override
  State<DanserSetupGate> createState() => _DanserSetupGateState();
}

class _DanserSetupGateState extends State<DanserSetupGate> {
  @override
  void initState() {
    super.initState();
    DanserService.instance.ensureReady();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DanserService.instance,
      builder: (context, _) {
        final svc = DanserService.instance;
        if (svc.isReady) return widget.child;
        return Scaffold(body: _buildBody(context, svc));
      },
    );
  }

  Widget _buildBody(BuildContext context, DanserService svc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: svc.error != null
              ? _ErrorPanel(error: svc.error!, loading: svc.isChecking)
              : _ProgressPanel(
                  statusMessage: svc.statusMessage,
                  progress: svc.progress,
                ),
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  final String statusMessage;
  final double? progress;

  const _ProgressPanel({required this.statusMessage, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.videocam_rounded, size: 56, color: Colors.pinkAccent),
        const SizedBox(height: 20),
        Text(
          '正在準備渲染引擎...',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress, minHeight: 6),
        ),
        if (statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            statusMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (progress != null) ...[
          const SizedBox(height: 6),
          Text(
            '${(progress! * 100).toStringAsFixed(1)} %',
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String error;
  final bool loading;

  const _ErrorPanel({required this.error, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
        const SizedBox(height: 16),
        Text(
          '安裝 danser-go 失敗',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: loading ? null : DanserService.instance.retrySetup,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(loading ? '重試中...' : '重試'),
        ),
      ],
    );
  }
}
