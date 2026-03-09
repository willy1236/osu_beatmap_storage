import 'dart:io';
import 'package:realm/realm.dart';
import '../models/osu_realm_models.dart';

/// 負責偵測 Realm schema 版本並以唯讀方式開啟 client.realm
abstract final class RealmService {
  // BeatmapSetInfo.schema 參照 RealmNamedFileUsage（Files 欄位），
  // 因此所有包含 BeatmapSetInfo 的 schema 列表都必須一起宣告這兩個型別。
  static final _baseSchemas = [
    BeatmapSetInfo.schema,
    BeatmapInfo.schema,
    BeatmapMetadata.schema,
    RulesetInfo.schema,
    RealmUser.schema,
    RealmFile.schema,
    RealmNamedFileUsage.schema,
  ];

  static final _schemas = _baseSchemas;

  static final _schemasWithScores = [..._baseSchemas, ScoreInfo.schema];

  /// 包含 RealmFile / RealmNamedFileUsage，供讀取譜面集檔案列表使用
  static final _schemasWithFiles = _baseSchemas;

  // 由大到小的候補版本清單（200 → 1）
  static final _likelyVersions = List.generate(200, (i) => 200 - i);

  static Future<Realm> open(String path) async {
    return _openWithSchemas(path, _schemas);
  }

  /// 開啟含有 ScoreInfo（回放）的 Realm，供回放列表頁面使用
  static Future<Realm> openWithScores(String path) async {
    return _openWithSchemas(path, _schemasWithScores);
  }

  /// 開啟含有 RealmFile / RealmNamedFileUsage 的 Realm，供渲染前複製譜面檔案使用
  static Future<Realm> openWithFiles(String path) async {
    return _openWithSchemas(path, _schemasWithFiles);
  }

  static Future<Realm> _openWithSchemas(
    String path,
    List<SchemaObject> schemas,
  ) async {
    if (!File(path).existsSync()) {
      throw Exception('找不到 Realm 檔案：$path');
    }

    String lastError = '';

    // ── 步驟 1：嘗試 version=51，從錯誤訊息解析實際版本 ──────────────────────
    try {
      return Realm(
        Configuration.local(
          schemas,
          path: path,
          isReadOnly: true,
          schemaVersion: 51,
        ),
      );
    } on RealmException catch (e) {
      lastError = e.toString();

      final candidates = RegExp(r'\b(\d{1,3})\b')
          .allMatches(lastError)
          .map((m) => int.tryParse(m.group(0)!))
          .nonNulls
          .where((n) => n > 0 && n < 300)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

      for (final v in candidates) {
        try {
          return Realm(
            Configuration.local(
              schemas,
              path: path,
              isReadOnly: true,
              schemaVersion: v,
            ),
          );
        } catch (_) {}
      }
    }

    // ── 步驟 2：退而求其次，依序嘗試常見 osu!lazer schema 版本 ──────────────
    for (final v in _likelyVersions) {
      try {
        return Realm(
          Configuration.local(
            schemas,
            path: path,
            isReadOnly: true,
            schemaVersion: v,
          ),
        );
      } catch (_) {}
    }

    throw Exception('無法開啟 Realm 檔案（嘗試所有已知 schema 版本皆失敗）。\n\n$lastError');
  }
}
