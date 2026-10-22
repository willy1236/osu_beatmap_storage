import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/cloud_entry.dart';
import 'auth_service.dart';

/// 一次上傳的結果類別
enum CloudSyncStatus {
  /// 全部批次都成功
  success,

  /// 被後端頻率限制擋下（429）；自動上傳應靜默跳過，其他觸發來源顯示「請稍後再試」
  rateLimited,

  /// 沒有可用的登入（未登入、refresh 失敗或後端回 401）
  unauthorized,

  /// 後端暫時連不上登入服務（503），稍後重試，不登出
  unavailable,

  /// 其他失敗（網路、逾時、5xx、422、回應格式錯誤）
  failed,

  /// 已經有一次上傳在進行
  busy,
}

class CloudSyncResult {
  const CloudSyncResult(
    this.status, {
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.retryAfter,
    this.message,
  });

  final CloudSyncStatus status;
  final int inserted;
  final int updated;

  /// 本機先過濾掉的（OnlineID ≤ 0）加上後端回報的筆數
  final int skipped;

  /// 429 時後端建議的等待秒數
  final int? retryAfter;
  final String? message;

  bool get ok => status == CloudSyncStatus.success;
}

/// 上傳進度（已送／總數，單位是筆）
class CloudSyncProgress {
  const CloudSyncProgress(this.sent, this.total);
  final int sent;
  final int total;
  double get fraction => total == 0 ? 0 : sent / total;
}

/// 把本機清單合併上傳到雲端（`POST /osu/beatmaps/merge`）。
/// token 一律從 [AuthService] 取得。同一時間只會有一次上傳。
class CloudSyncService extends ChangeNotifier {
  CloudSyncService({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
    String? baseUrl,
    DateTime Function()? now,
    String Function()? newSyncId,
    Duration? requestTimeout,
  }) : _http = httpClient ?? http.Client(),
       _token = tokenProvider ?? (() => AuthService.instance.accessToken()),
       _baseUrl = baseUrl ?? kApiBase,
       _now = now ?? DateTime.now,
       _newSyncId = newSyncId ?? _randomSyncId,
       _timeout = requestTimeout ?? const Duration(seconds: 60);

  static final CloudSyncService instance = CloudSyncService();

  /// 後端每批最多 1000 筆
  static const batchSize = 1000;

  /// 後端對同一個 sync_id 的有效期（第一批之後這麼久）；重試沿用 sync_id 不能超過
  static const syncWindow = Duration(minutes: 10);

  final http.Client _http;
  final Future<String?> Function() _token;
  final String _baseUrl;
  final DateTime Function() _now;
  final String Function() _newSyncId;
  final Duration _timeout;

  CloudSyncProgress? _progress;
  String? _lastError;
  CloudSyncResult? _lastResult;
  bool _uploading = false;

  // 上次失敗的上傳：10 分鐘內重試沿用同一個 sync_id，後端就不會把重試當成新的一次同步而回 429
  String? _retrySyncId;
  String? _retryTrigger;
  DateTime? _retryStartedAt;

  /// 上傳中為已送／總數，閒置時為 null
  CloudSyncProgress? get progress => _progress;
  bool get uploading => _uploading;

  /// 最近一次上傳失敗的說明（供狀態區顯示）；成功或下次上傳開始時清除。
  /// 被頻率限制擋下不算錯誤，不會設在這裡
  String? get lastError => _lastError;
  CloudSyncResult? get lastResult => _lastResult;

  static String _randomSyncId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// 上傳 [entries]（OnlineID ≤ 0 的先在本機略過），[trigger] 為 `manual`、`auto` 或 `csv`。
  /// 不會丟例外，結果看回傳值；UI 另可監聽 [progress] 與 [lastError]。
  Future<CloudSyncResult> upload(
    List<CloudEntry> entries, {
    required String trigger,
  }) async {
    if (_uploading) return const CloudSyncResult(CloudSyncStatus.busy);
    _uploading = true;
    _lastError = null;
    final valid = entries.where((e) => e.onlineId > 0).toList();
    final localSkipped = entries.length - valid.length;
    _progress = CloudSyncProgress(0, valid.length);
    notifyListeners();

    final syncId = _syncIdFor(trigger);
    CloudSyncResult result;
    try {
      result = await _run(valid, trigger, syncId, localSkipped);
    } catch (e) {
      result = CloudSyncResult(
        CloudSyncStatus.failed,
        message: '上傳失敗：${_describe(e)}',
      );
    }

    if (result.status == CloudSyncStatus.success ||
        result.status == CloudSyncStatus.rateLimited) {
      // 成功：同步完成。429：沒有寫入任何資料，下次是全新的同步
      _retrySyncId = null;
    } else {
      _lastError = result.message;
    }
    _lastResult = result;
    _uploading = false;
    _progress = null;
    notifyListeners();
    return result;
  }

  String _syncIdFor(String trigger) {
    final id = _retrySyncId;
    final started = _retryStartedAt;
    if (id != null &&
        _retryTrigger == trigger &&
        started != null &&
        _now().difference(started) < syncWindow) {
      return id;
    }
    _retrySyncId = _newSyncId();
    _retryTrigger = trigger;
    _retryStartedAt = _now();
    return _retrySyncId!;
  }

  Future<CloudSyncResult> _run(
    List<CloudEntry> entries,
    String trigger,
    String syncId,
    int localSkipped,
  ) async {
    var inserted = 0, updated = 0, skipped = localSkipped;
    // 沒有可傳的資料就不呼叫後端（也不耗用頻率額度）
    if (entries.isEmpty) {
      return CloudSyncResult(CloudSyncStatus.success, skipped: skipped);
    }
    for (var i = 0; i < entries.length; i += batchSize) {
      final batch = entries.sublist(i, min(i + batchSize, entries.length));
      final token = await _token();
      if (token == null) {
        return const CloudSyncResult(
          CloudSyncStatus.unauthorized,
          message: '未登入或登入已失效，請重新登入',
        );
      }
      final http.Response resp;
      try {
        resp = await _http
            .post(
              Uri.parse('$_baseUrl/osu/beatmaps/merge'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: utf8.encode(
                jsonEncode({
                  'trigger': trigger,
                  'sync_id': syncId,
                  'entries': [for (final e in batch) e.toJson()],
                }),
              ),
            )
            .timeout(_timeout);
      } catch (e) {
        return CloudSyncResult(
          CloudSyncStatus.failed,
          message: '上傳失敗：${_describe(e)}',
        );
      }

      if (resp.statusCode != 200) return _errorResult(resp);
      try {
        final body =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        inserted += body['inserted'] as int;
        updated += body['updated'] as int;
        skipped += body['skipped'] as int;
      } catch (_) {
        return const CloudSyncResult(
          CloudSyncStatus.failed,
          message: '上傳失敗：伺服器回應格式錯誤',
        );
      }
      _progress = CloudSyncProgress(i + batch.length, entries.length);
      notifyListeners();
    }
    return CloudSyncResult(
      CloudSyncStatus.success,
      inserted: inserted,
      updated: updated,
      skipped: skipped,
    );
  }

  CloudSyncResult _errorResult(http.Response resp) {
    String? err, description;
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map) {
        err = body['err'] as String?;
        description = body['description'] as String?;
      }
    } catch (_) {}
    switch (resp.statusCode) {
      case 429:
        return CloudSyncResult(
          CloudSyncStatus.rateLimited,
          retryAfter: int.tryParse(resp.headers['retry-after'] ?? ''),
          message: '請稍後再試',
        );
      case 401:
        return const CloudSyncResult(
          CloudSyncStatus.unauthorized,
          message: '登入已失效，請重新登入',
        );
      case 503:
        return const CloudSyncResult(
          CloudSyncStatus.unavailable,
          message: '登入服務暫時無法使用，請稍後再試',
        );
      default:
        final detail = [
          '${resp.statusCode}',
          ?err,
        ].join(' ');
        return CloudSyncResult(
          CloudSyncStatus.failed,
          message: '上傳失敗（$detail${description == null ? '' : '：$description'}）',
        );
    }
  }

  static String _describe(Object e) =>
      e is TimeoutException ? '連線逾時' : e.toString();
}
