import 'package:realm/realm.dart';

part 'osu_realm_models.realm.dart';

// ── 嵌入式：osu! 使用者 ──────────────────────────────────────────────────────
@RealmModel(ObjectType.embeddedObject)
class _RealmUser {
  @MapTo('OnlineID')
  late int onlineID;

  @MapTo('Username')
  late String? username;

  @MapTo('CountryCode')
  late String? countryCode;
}

// ── 圖譜後設資料 ─────────────────────────────────────────────────────────────
@RealmModel()
class _BeatmapMetadata {
  @MapTo('Title')
  late String? title;

  @MapTo('TitleUnicode')
  late String? titleUnicode;

  @MapTo('Artist')
  late String? artist;

  @MapTo('ArtistUnicode')
  late String? artistUnicode;

  @MapTo('Author')
  late _RealmUser? author;

  @MapTo('Source')
  late String? source;

  @MapTo('Tags')
  late String? tags;

  @MapTo('PreviewTime')
  late int previewTime;

  @MapTo('AudioFile')
  late String? audioFile;

  @MapTo('BackgroundFile')
  late String? backgroundFile;
}

// ── 遊戲模式 ──────────────────────────────────────────────────────────────────
@RealmModel()
@MapTo('Ruleset')
class _RulesetInfo {
  @PrimaryKey()
  @MapTo('ShortName')
  late String? shortName;

  @MapTo('OnlineID')
  late int onlineID;

  @MapTo('Name')
  late String? name;

  @MapTo('InstantiationInfo')
  late String? instantiationInfo;

  @MapTo('LastAppliedDifficultyVersion')
  late int lastAppliedDifficultyVersion;

  @MapTo('Available')
  late bool available;
}

// ── 單一難度 ──────────────────────────────────────────────────────────────────
@RealmModel()
@MapTo('Beatmap')
class _BeatmapInfo {
  @PrimaryKey()
  @MapTo('ID')
  late Uuid id;

  @MapTo('DifficultyName')
  late String? difficultyName;

  @MapTo('Ruleset')
  late _RulesetInfo? ruleset;

  @MapTo('Metadata')
  late _BeatmapMetadata? metadata;

  @MapTo('Status')
  late int status;

  @MapTo('Hidden')
  late bool hidden;

  @MapTo('OnlineID')
  late int onlineID;

  @MapTo('Length')
  late double length;

  @MapTo('BPM')
  late double bpm;

  @MapTo('Hash')
  late String? hash;

  @MapTo('StarRating')
  late double starRating;

  @MapTo('MD5Hash')
  late String? md5Hash;
}

// ── Realm 物理檔案 ────────────────────────────────────────────────────────────
@RealmModel()
@MapTo('File')
class _RealmFile {
  @PrimaryKey()
  @MapTo('Hash')
  late String? hash;
}

// ── 已命名的檔案參照（嵌入式）────────────────────────────────────────────────────────────────────────
@RealmModel(ObjectType.embeddedObject)
@MapTo('RealmNamedFileUsage')
class _RealmNamedFileUsage {
  @MapTo('File')
  late _RealmFile? file;

  @MapTo('Filename')
  late String? filename;
}

// ── 圖譜集 ────────────────────────────────────────────────────────────────────
@RealmModel()
@MapTo('BeatmapSet')
class _BeatmapSetInfo {
  @PrimaryKey()
  @MapTo('ID')
  late Uuid id;

  @MapTo('OnlineID')
  late int onlineID;

  @MapTo('DateAdded')
  late DateTime dateAdded;

  @MapTo('DateSubmitted')
  late DateTime? dateSubmitted;

  @MapTo('Status')
  late int status;

  @MapTo('DeletePending')
  late bool deletePending;

  @MapTo('Hash')
  late String? hash;

  @MapTo('Protected')
  late bool isProtected;

  @MapTo('Beatmaps')
  late List<_BeatmapInfo> beatmaps;

  @MapTo('Files')
  late List<_RealmNamedFileUsage> files;
}

// ── Skin ──────────────────────────────────────────────────────────────────────
@RealmModel()
@MapTo('Skin')
class _SkinInfo {
  @PrimaryKey()
  @MapTo('ID')
  late Uuid id;

  @MapTo('Name')
  late String? name;

  @MapTo('Creator')
  late String? creator;

  @MapTo('Hash')
  late String? hash;

  @MapTo('Protected')
  late bool isProtected;

  @MapTo('Files')
  late List<_RealmNamedFileUsage> files;
}

// ── 點數紀錄（回放） ──────────────────────────────────────────────────────────
@RealmModel()
@MapTo('Score')
class _ScoreInfo {
  @PrimaryKey()
  @MapTo('ID')
  late Uuid id;

  @MapTo('BeatmapInfo')
  late _BeatmapInfo? beatmapInfo;

  @MapTo('BeatmapHash')
  late String? beatmapHash;

  @MapTo('Ruleset')
  late _RulesetInfo? ruleset;

  @MapTo('Hash')
  late String? hash;

  @MapTo('DeletePending')
  late bool deletePending;

  @MapTo('TotalScore')
  late int totalScore;

  @MapTo('MaxCombo')
  late int maxCombo;

  @MapTo('Accuracy')
  late double accuracy;

  @MapTo('Rank')
  late int rank;

  @MapTo('Date')
  late DateTime date;

  @MapTo('PP')
  late double? pp;
}
