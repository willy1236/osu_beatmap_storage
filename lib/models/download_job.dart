import 'package:realm/realm.dart';

enum DownloadStatus { queued, downloading, done, skipped, failed, cancelled }

class DownloadJob {
  final int onlineID;
  final String title;
  DownloadStatus status;
  double progress;
  String? error;
  CancellationToken? cancellationToken;

  DownloadJob({required this.onlineID, required this.title})
    : status = DownloadStatus.queued,
      progress = 0;
}
