import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:realm/realm.dart';
import '../constants.dart';
import '../models/download_job.dart';

class DownloadService extends ChangeNotifier {
  static final instance = DownloadService._();
  DownloadService._();

  String _saveDir = '';
  final List<DownloadJob> jobs = [];
  bool _running = false;
  final _client = http.Client();

  DownloadJob? jobFor(int onlineID) {
    final matches = jobs.where((j) => j.onlineID == onlineID);
    return matches.isEmpty ? null : matches.first;
  }

  static String get downloadsPath => '${Directory.current.path}/osu_downloads';

  Future<String> get _dir async {
    if (_saveDir.isNotEmpty) return _saveDir;
    _saveDir = downloadsPath;
    await Directory(_saveDir).create(recursive: true);
    return _saveDir;
  }

  void enqueue(int onlineID, String title) {
    if (onlineID <= 0) return;
    if (jobs.any((j) => j.onlineID == onlineID)) return;
    jobs.add(DownloadJob(onlineID: onlineID, title: title));
    notifyListeners();
    _pump();
  }

  void retry(DownloadJob job) {
    job.status = DownloadStatus.queued;
    job.progress = 0;
    job.error = null;
    job.cancellationToken = null;
    notifyListeners();
    _pump();
  }

  void enqueueAll(Iterable<({int onlineID, String title})> items) {
    bool added = false;
    for (final item in items) {
      if (item.onlineID <= 0) continue;
      final existing = jobFor(item.onlineID);
      if (existing != null &&
          existing.status != DownloadStatus.failed &&
          existing.status != DownloadStatus.cancelled) {
        continue;
      }
      if (existing != null) {
        existing.status = DownloadStatus.queued;
        existing.progress = 0;
        existing.error = null;
        existing.cancellationToken = null;
      } else {
        jobs.add(DownloadJob(onlineID: item.onlineID, title: item.title));
      }
      added = true;
    }
    if (added) {
      notifyListeners();
      _pump();
    }
  }

  void cancel(DownloadJob job) {
    if (job.status == DownloadStatus.done ||
        job.status == DownloadStatus.skipped ||
        job.status == DownloadStatus.cancelled) {
      return;
    }
    job.cancellationToken?.cancel();
    job.cancellationToken = null;
    job.status = DownloadStatus.cancelled;
    job.progress = 0;
    notifyListeners();
  }

  void cancelAll() {
    for (final job in jobs) {
      if (job.status == DownloadStatus.queued ||
          job.status == DownloadStatus.downloading) {
        job.cancellationToken?.cancel();
        job.cancellationToken = null;
        job.status = DownloadStatus.cancelled;
        job.progress = 0;
      }
    }
    notifyListeners();
  }

  DownloadJob? _nextQueued() {
    for (final j in jobs) {
      if (j.status == DownloadStatus.queued) return j;
    }
    return null;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final job = _nextQueued();
        if (job == null) break;
        if (job.status == DownloadStatus.cancelled) continue;
        await _run(job);
        if (_nextQueued() != null) await Future.delayed(kDownloadInterDelay);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(DownloadJob job) async {
    final token = CancellationToken();
    job.cancellationToken = token;
    job.status = DownloadStatus.downloading;
    job.progress = 0;
    notifyListeners();

    final dir = await _dir;
    final safeTitle = job.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '$dir/${job.onlineID} $safeTitle.osz';

    if (File(filePath).existsSync()) {
      job.status = DownloadStatus.skipped;
      job.progress = 1;
      job.cancellationToken = null;
      notifyListeners();
      return;
    }

    final tempPath = '$filePath.tmp';
    for (var attempt = 0; attempt < 3; attempt++) {
      if (token.isCancelled) {
        try {
          File(tempPath).deleteSync();
        } catch (_) {}
        job.cancellationToken = null;
        notifyListeners();
        return;
      }
      try {
        final uri = Uri.parse('$kDownloadBaseUrl${job.onlineID}');
        final req = http.Request('GET', uri)
          ..headers['User-Agent'] = 'osu-beatmap-storage/1.0';
        final resp = await _client.send(req);

        if (resp.statusCode == 404) {
          job.status = DownloadStatus.failed;
          job.error = 'osu.direct 找不到此圖譜 (404)';
          job.cancellationToken = null;
          notifyListeners();
          return;
        }
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }

        final total = resp.contentLength ?? 0;
        var received = 0;
        final sink = File(tempPath).openWrite();
        var closed = false;
        try {
          await for (final chunk in resp.stream) {
            if (token.isCancelled) break;
            sink.add(chunk);
            received += chunk.length;
            if (total > 0) {
              job.progress = received / total;
              notifyListeners();
            }
          }
          await sink.flush();
        } catch (e) {
          closed = true;
          await sink.close();
          rethrow;
        } finally {
          if (!closed) await sink.close();
        }

        if (token.isCancelled) {
          try {
            File(tempPath).deleteSync();
          } catch (_) {}
          job.cancellationToken = null;
          notifyListeners();
          return;
        }

        await File(tempPath).rename(filePath);
        job.status = DownloadStatus.done;
        job.progress = 1;
        job.cancellationToken = null;
        notifyListeners();
        return;
      } catch (e) {
        try {
          final tmp = File(tempPath);
          if (tmp.existsSync()) await tmp.delete();
        } catch (_) {}
        if (token.isCancelled || attempt == 2) {
          if (!token.isCancelled) {
            job.status = DownloadStatus.failed;
            job.error = e.toString();
          }
          job.cancellationToken = null;
          notifyListeners();
          return;
        }
        await Future.delayed(const Duration(seconds: 5));
      }
    }
    job.cancellationToken = null;
  }
}
