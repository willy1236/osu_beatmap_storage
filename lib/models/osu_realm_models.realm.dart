// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'osu_realm_models.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
class RealmUser extends _RealmUser
    with RealmEntity, RealmObjectBase, EmbeddedObject {
  RealmUser(int onlineID, {String? username, String? countryCode}) {
    RealmObjectBase.set(this, 'OnlineID', onlineID);
    RealmObjectBase.set(this, 'Username', username);
    RealmObjectBase.set(this, 'CountryCode', countryCode);
  }

  RealmUser._();

  @override
  int get onlineID => RealmObjectBase.get<int>(this, 'OnlineID') as int;
  @override
  set onlineID(int value) => RealmObjectBase.set(this, 'OnlineID', value);

  @override
  String? get username =>
      RealmObjectBase.get<String>(this, 'Username') as String?;
  @override
  set username(String? value) => RealmObjectBase.set(this, 'Username', value);

  @override
  String? get countryCode =>
      RealmObjectBase.get<String>(this, 'CountryCode') as String?;
  @override
  set countryCode(String? value) =>
      RealmObjectBase.set(this, 'CountryCode', value);

  @override
  Stream<RealmObjectChanges<RealmUser>> get changes =>
      RealmObjectBase.getChanges<RealmUser>(this);

  @override
  Stream<RealmObjectChanges<RealmUser>> changesFor([List<String>? keyPaths]) =>
      RealmObjectBase.getChangesFor<RealmUser>(this, keyPaths);

  @override
  RealmUser freeze() => RealmObjectBase.freezeObject<RealmUser>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      'OnlineID': onlineID.toEJson(),
      'Username': username.toEJson(),
      'CountryCode': countryCode.toEJson(),
    };
  }

  static EJsonValue _toEJson(RealmUser value) => value.toEJson();
  static RealmUser _fromEJson(EJsonValue ejson) {
    if (ejson is! Map<String, dynamic>) return raiseInvalidEJson(ejson);
    return switch (ejson) {
      {'OnlineID': EJsonValue onlineID} => RealmUser(
        fromEJson(onlineID),
        username: fromEJson(ejson['Username']),
        countryCode: fromEJson(ejson['CountryCode']),
      ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(RealmUser._);
    register(_toEJson, _fromEJson);
    return const SchemaObject(
      ObjectType.embeddedObject,
      RealmUser,
      'RealmUser',
      [
        SchemaProperty('onlineID', RealmPropertyType.int, mapTo: 'OnlineID'),
        SchemaProperty(
          'username',
          RealmPropertyType.string,
          mapTo: 'Username',
          optional: true,
        ),
        SchemaProperty(
          'countryCode',
          RealmPropertyType.string,
          mapTo: 'CountryCode',
          optional: true,
        ),
      ],
    );
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}

class BeatmapMetadata extends _BeatmapMetadata
    with RealmEntity, RealmObjectBase, RealmObject {
  BeatmapMetadata(
    int previewTime, {
    String? title,
    String? titleUnicode,
    String? artist,
    String? artistUnicode,
    RealmUser? author,
    String? source,
    String? tags,
    String? audioFile,
    String? backgroundFile,
  }) {
    RealmObjectBase.set(this, 'Title', title);
    RealmObjectBase.set(this, 'TitleUnicode', titleUnicode);
    RealmObjectBase.set(this, 'Artist', artist);
    RealmObjectBase.set(this, 'ArtistUnicode', artistUnicode);
    RealmObjectBase.set(this, 'Author', author);
    RealmObjectBase.set(this, 'Source', source);
    RealmObjectBase.set(this, 'Tags', tags);
    RealmObjectBase.set(this, 'PreviewTime', previewTime);
    RealmObjectBase.set(this, 'AudioFile', audioFile);
    RealmObjectBase.set(this, 'BackgroundFile', backgroundFile);
  }

  BeatmapMetadata._();

  @override
  String? get title => RealmObjectBase.get<String>(this, 'Title') as String?;
  @override
  set title(String? value) => RealmObjectBase.set(this, 'Title', value);

  @override
  String? get titleUnicode =>
      RealmObjectBase.get<String>(this, 'TitleUnicode') as String?;
  @override
  set titleUnicode(String? value) =>
      RealmObjectBase.set(this, 'TitleUnicode', value);

  @override
  String? get artist => RealmObjectBase.get<String>(this, 'Artist') as String?;
  @override
  set artist(String? value) => RealmObjectBase.set(this, 'Artist', value);

  @override
  String? get artistUnicode =>
      RealmObjectBase.get<String>(this, 'ArtistUnicode') as String?;
  @override
  set artistUnicode(String? value) =>
      RealmObjectBase.set(this, 'ArtistUnicode', value);

  @override
  RealmUser? get author =>
      RealmObjectBase.get<RealmUser>(this, 'Author') as RealmUser?;
  @override
  set author(covariant RealmUser? value) =>
      RealmObjectBase.set(this, 'Author', value);

  @override
  String? get source => RealmObjectBase.get<String>(this, 'Source') as String?;
  @override
  set source(String? value) => RealmObjectBase.set(this, 'Source', value);

  @override
  String? get tags => RealmObjectBase.get<String>(this, 'Tags') as String?;
  @override
  set tags(String? value) => RealmObjectBase.set(this, 'Tags', value);

  @override
  int get previewTime => RealmObjectBase.get<int>(this, 'PreviewTime') as int;
  @override
  set previewTime(int value) => RealmObjectBase.set(this, 'PreviewTime', value);

  @override
  String? get audioFile =>
      RealmObjectBase.get<String>(this, 'AudioFile') as String?;
  @override
  set audioFile(String? value) => RealmObjectBase.set(this, 'AudioFile', value);

  @override
  String? get backgroundFile =>
      RealmObjectBase.get<String>(this, 'BackgroundFile') as String?;
  @override
  set backgroundFile(String? value) =>
      RealmObjectBase.set(this, 'BackgroundFile', value);

  @override
  Stream<RealmObjectChanges<BeatmapMetadata>> get changes =>
      RealmObjectBase.getChanges<BeatmapMetadata>(this);

  @override
  Stream<RealmObjectChanges<BeatmapMetadata>> changesFor([
    List<String>? keyPaths,
  ]) => RealmObjectBase.getChangesFor<BeatmapMetadata>(this, keyPaths);

  @override
  BeatmapMetadata freeze() =>
      RealmObjectBase.freezeObject<BeatmapMetadata>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      'Title': title.toEJson(),
      'TitleUnicode': titleUnicode.toEJson(),
      'Artist': artist.toEJson(),
      'ArtistUnicode': artistUnicode.toEJson(),
      'Author': author.toEJson(),
      'Source': source.toEJson(),
      'Tags': tags.toEJson(),
      'PreviewTime': previewTime.toEJson(),
      'AudioFile': audioFile.toEJson(),
      'BackgroundFile': backgroundFile.toEJson(),
    };
  }

  static EJsonValue _toEJson(BeatmapMetadata value) => value.toEJson();
  static BeatmapMetadata _fromEJson(EJsonValue ejson) {
    if (ejson is! Map<String, dynamic>) return raiseInvalidEJson(ejson);
    return switch (ejson) {
      {'PreviewTime': EJsonValue previewTime} => BeatmapMetadata(
        fromEJson(previewTime),
        title: fromEJson(ejson['Title']),
        titleUnicode: fromEJson(ejson['TitleUnicode']),
        artist: fromEJson(ejson['Artist']),
        artistUnicode: fromEJson(ejson['ArtistUnicode']),
        author: fromEJson(ejson['Author']),
        source: fromEJson(ejson['Source']),
        tags: fromEJson(ejson['Tags']),
        audioFile: fromEJson(ejson['AudioFile']),
        backgroundFile: fromEJson(ejson['BackgroundFile']),
      ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(BeatmapMetadata._);
    register(_toEJson, _fromEJson);
    return const SchemaObject(
      ObjectType.realmObject,
      BeatmapMetadata,
      'BeatmapMetadata',
      [
        SchemaProperty(
          'title',
          RealmPropertyType.string,
          mapTo: 'Title',
          optional: true,
        ),
        SchemaProperty(
          'titleUnicode',
          RealmPropertyType.string,
          mapTo: 'TitleUnicode',
          optional: true,
        ),
        SchemaProperty(
          'artist',
          RealmPropertyType.string,
          mapTo: 'Artist',
          optional: true,
        ),
        SchemaProperty(
          'artistUnicode',
          RealmPropertyType.string,
          mapTo: 'ArtistUnicode',
          optional: true,
        ),
        SchemaProperty(
          'author',
          RealmPropertyType.object,
          mapTo: 'Author',
          optional: true,
          linkTarget: 'RealmUser',
        ),
        SchemaProperty(
          'source',
          RealmPropertyType.string,
          mapTo: 'Source',
          optional: true,
        ),
        SchemaProperty(
          'tags',
          RealmPropertyType.string,
          mapTo: 'Tags',
          optional: true,
        ),
        SchemaProperty(
          'previewTime',
          RealmPropertyType.int,
          mapTo: 'PreviewTime',
        ),
        SchemaProperty(
          'audioFile',
          RealmPropertyType.string,
          mapTo: 'AudioFile',
          optional: true,
        ),
        SchemaProperty(
          'backgroundFile',
          RealmPropertyType.string,
          mapTo: 'BackgroundFile',
          optional: true,
        ),
      ],
    );
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}

class RulesetInfo extends _RulesetInfo
    with RealmEntity, RealmObjectBase, RealmObject {
  RulesetInfo(
    String? shortName,
    int onlineID,
    int lastAppliedDifficultyVersion,
    bool available, {
    String? name,
    String? instantiationInfo,
  }) {
    RealmObjectBase.set(this, 'ShortName', shortName);
    RealmObjectBase.set(this, 'OnlineID', onlineID);
    RealmObjectBase.set(this, 'Name', name);
    RealmObjectBase.set(this, 'InstantiationInfo', instantiationInfo);
    RealmObjectBase.set(
      this,
      'LastAppliedDifficultyVersion',
      lastAppliedDifficultyVersion,
    );
    RealmObjectBase.set(this, 'Available', available);
  }

  RulesetInfo._();

  @override
  String? get shortName =>
      RealmObjectBase.get<String>(this, 'ShortName') as String?;
  @override
  set shortName(String? value) => RealmObjectBase.set(this, 'ShortName', value);

  @override
  int get onlineID => RealmObjectBase.get<int>(this, 'OnlineID') as int;
  @override
  set onlineID(int value) => RealmObjectBase.set(this, 'OnlineID', value);

  @override
  String? get name => RealmObjectBase.get<String>(this, 'Name') as String?;
  @override
  set name(String? value) => RealmObjectBase.set(this, 'Name', value);

  @override
  String? get instantiationInfo =>
      RealmObjectBase.get<String>(this, 'InstantiationInfo') as String?;
  @override
  set instantiationInfo(String? value) =>
      RealmObjectBase.set(this, 'InstantiationInfo', value);

  @override
  int get lastAppliedDifficultyVersion =>
      RealmObjectBase.get<int>(this, 'LastAppliedDifficultyVersion') as int;
  @override
  set lastAppliedDifficultyVersion(int value) =>
      RealmObjectBase.set(this, 'LastAppliedDifficultyVersion', value);

  @override
  bool get available => RealmObjectBase.get<bool>(this, 'Available') as bool;
  @override
  set available(bool value) => RealmObjectBase.set(this, 'Available', value);

  @override
  Stream<RealmObjectChanges<RulesetInfo>> get changes =>
      RealmObjectBase.getChanges<RulesetInfo>(this);

  @override
  Stream<RealmObjectChanges<RulesetInfo>> changesFor([
    List<String>? keyPaths,
  ]) => RealmObjectBase.getChangesFor<RulesetInfo>(this, keyPaths);

  @override
  RulesetInfo freeze() => RealmObjectBase.freezeObject<RulesetInfo>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      'ShortName': shortName.toEJson(),
      'OnlineID': onlineID.toEJson(),
      'Name': name.toEJson(),
      'InstantiationInfo': instantiationInfo.toEJson(),
      'LastAppliedDifficultyVersion': lastAppliedDifficultyVersion.toEJson(),
      'Available': available.toEJson(),
    };
  }

  static EJsonValue _toEJson(RulesetInfo value) => value.toEJson();
  static RulesetInfo _fromEJson(EJsonValue ejson) {
    if (ejson is! Map<String, dynamic>) return raiseInvalidEJson(ejson);
    return switch (ejson) {
      {
        'ShortName': EJsonValue shortName,
        'OnlineID': EJsonValue onlineID,
        'LastAppliedDifficultyVersion': EJsonValue lastAppliedDifficultyVersion,
        'Available': EJsonValue available,
      } =>
        RulesetInfo(
          fromEJson(ejson['ShortName']),
          fromEJson(onlineID),
          fromEJson(lastAppliedDifficultyVersion),
          fromEJson(available),
          name: fromEJson(ejson['Name']),
          instantiationInfo: fromEJson(ejson['InstantiationInfo']),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(RulesetInfo._);
    register(_toEJson, _fromEJson);
    return const SchemaObject(ObjectType.realmObject, RulesetInfo, 'Ruleset', [
      SchemaProperty(
        'shortName',
        RealmPropertyType.string,
        mapTo: 'ShortName',
        optional: true,
        primaryKey: true,
      ),
      SchemaProperty('onlineID', RealmPropertyType.int, mapTo: 'OnlineID'),
      SchemaProperty(
        'name',
        RealmPropertyType.string,
        mapTo: 'Name',
        optional: true,
      ),
      SchemaProperty(
        'instantiationInfo',
        RealmPropertyType.string,
        mapTo: 'InstantiationInfo',
        optional: true,
      ),
      SchemaProperty(
        'lastAppliedDifficultyVersion',
        RealmPropertyType.int,
        mapTo: 'LastAppliedDifficultyVersion',
      ),
      SchemaProperty('available', RealmPropertyType.bool, mapTo: 'Available'),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}

class BeatmapInfo extends _BeatmapInfo
    with RealmEntity, RealmObjectBase, RealmObject {
  BeatmapInfo(
    Uuid id,
    int status,
    bool hidden,
    int onlineID,
    double length,
    double bpm,
    double starRating, {
    String? difficultyName,
    RulesetInfo? ruleset,
    BeatmapMetadata? metadata,
    String? hash,
    String? md5Hash,
  }) {
    RealmObjectBase.set(this, 'ID', id);
    RealmObjectBase.set(this, 'DifficultyName', difficultyName);
    RealmObjectBase.set(this, 'Ruleset', ruleset);
    RealmObjectBase.set(this, 'Metadata', metadata);
    RealmObjectBase.set(this, 'Status', status);
    RealmObjectBase.set(this, 'Hidden', hidden);
    RealmObjectBase.set(this, 'OnlineID', onlineID);
    RealmObjectBase.set(this, 'Length', length);
    RealmObjectBase.set(this, 'BPM', bpm);
    RealmObjectBase.set(this, 'Hash', hash);
    RealmObjectBase.set(this, 'StarRating', starRating);
    RealmObjectBase.set(this, 'MD5Hash', md5Hash);
  }

  BeatmapInfo._();

  @override
  Uuid get id => RealmObjectBase.get<Uuid>(this, 'ID') as Uuid;
  @override
  set id(Uuid value) => RealmObjectBase.set(this, 'ID', value);

  @override
  String? get difficultyName =>
      RealmObjectBase.get<String>(this, 'DifficultyName') as String?;
  @override
  set difficultyName(String? value) =>
      RealmObjectBase.set(this, 'DifficultyName', value);

  @override
  RulesetInfo? get ruleset =>
      RealmObjectBase.get<RulesetInfo>(this, 'Ruleset') as RulesetInfo?;
  @override
  set ruleset(covariant RulesetInfo? value) =>
      RealmObjectBase.set(this, 'Ruleset', value);

  @override
  BeatmapMetadata? get metadata =>
      RealmObjectBase.get<BeatmapMetadata>(this, 'Metadata')
          as BeatmapMetadata?;
  @override
  set metadata(covariant BeatmapMetadata? value) =>
      RealmObjectBase.set(this, 'Metadata', value);

  @override
  int get status => RealmObjectBase.get<int>(this, 'Status') as int;
  @override
  set status(int value) => RealmObjectBase.set(this, 'Status', value);

  @override
  bool get hidden => RealmObjectBase.get<bool>(this, 'Hidden') as bool;
  @override
  set hidden(bool value) => RealmObjectBase.set(this, 'Hidden', value);

  @override
  int get onlineID => RealmObjectBase.get<int>(this, 'OnlineID') as int;
  @override
  set onlineID(int value) => RealmObjectBase.set(this, 'OnlineID', value);

  @override
  double get length => RealmObjectBase.get<double>(this, 'Length') as double;
  @override
  set length(double value) => RealmObjectBase.set(this, 'Length', value);

  @override
  double get bpm => RealmObjectBase.get<double>(this, 'BPM') as double;
  @override
  set bpm(double value) => RealmObjectBase.set(this, 'BPM', value);

  @override
  String? get hash => RealmObjectBase.get<String>(this, 'Hash') as String?;
  @override
  set hash(String? value) => RealmObjectBase.set(this, 'Hash', value);

  @override
  double get starRating =>
      RealmObjectBase.get<double>(this, 'StarRating') as double;
  @override
  set starRating(double value) =>
      RealmObjectBase.set(this, 'StarRating', value);

  @override
  String? get md5Hash =>
      RealmObjectBase.get<String>(this, 'MD5Hash') as String?;
  @override
  set md5Hash(String? value) => RealmObjectBase.set(this, 'MD5Hash', value);

  @override
  Stream<RealmObjectChanges<BeatmapInfo>> get changes =>
      RealmObjectBase.getChanges<BeatmapInfo>(this);

  @override
  Stream<RealmObjectChanges<BeatmapInfo>> changesFor([
    List<String>? keyPaths,
  ]) => RealmObjectBase.getChangesFor<BeatmapInfo>(this, keyPaths);

  @override
  BeatmapInfo freeze() => RealmObjectBase.freezeObject<BeatmapInfo>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      'ID': id.toEJson(),
      'DifficultyName': difficultyName.toEJson(),
      'Ruleset': ruleset.toEJson(),
      'Metadata': metadata.toEJson(),
      'Status': status.toEJson(),
      'Hidden': hidden.toEJson(),
      'OnlineID': onlineID.toEJson(),
      'Length': length.toEJson(),
      'BPM': bpm.toEJson(),
      'Hash': hash.toEJson(),
      'StarRating': starRating.toEJson(),
      'MD5Hash': md5Hash.toEJson(),
    };
  }

  static EJsonValue _toEJson(BeatmapInfo value) => value.toEJson();
  static BeatmapInfo _fromEJson(EJsonValue ejson) {
    if (ejson is! Map<String, dynamic>) return raiseInvalidEJson(ejson);
    return switch (ejson) {
      {
        'ID': EJsonValue id,
        'Status': EJsonValue status,
        'Hidden': EJsonValue hidden,
        'OnlineID': EJsonValue onlineID,
        'Length': EJsonValue length,
        'BPM': EJsonValue bpm,
        'StarRating': EJsonValue starRating,
      } =>
        BeatmapInfo(
          fromEJson(id),
          fromEJson(status),
          fromEJson(hidden),
          fromEJson(onlineID),
          fromEJson(length),
          fromEJson(bpm),
          fromEJson(starRating),
          difficultyName: fromEJson(ejson['DifficultyName']),
          ruleset: fromEJson(ejson['Ruleset']),
          metadata: fromEJson(ejson['Metadata']),
          hash: fromEJson(ejson['Hash']),
          md5Hash: fromEJson(ejson['MD5Hash']),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(BeatmapInfo._);
    register(_toEJson, _fromEJson);
    return const SchemaObject(ObjectType.realmObject, BeatmapInfo, 'Beatmap', [
      SchemaProperty(
        'id',
        RealmPropertyType.uuid,
        mapTo: 'ID',
        primaryKey: true,
      ),
      SchemaProperty(
        'difficultyName',
        RealmPropertyType.string,
        mapTo: 'DifficultyName',
        optional: true,
      ),
      SchemaProperty(
        'ruleset',
        RealmPropertyType.object,
        mapTo: 'Ruleset',
        optional: true,
        linkTarget: 'Ruleset',
      ),
      SchemaProperty(
        'metadata',
        RealmPropertyType.object,
        mapTo: 'Metadata',
        optional: true,
        linkTarget: 'BeatmapMetadata',
      ),
      SchemaProperty('status', RealmPropertyType.int, mapTo: 'Status'),
      SchemaProperty('hidden', RealmPropertyType.bool, mapTo: 'Hidden'),
      SchemaProperty('onlineID', RealmPropertyType.int, mapTo: 'OnlineID'),
      SchemaProperty('length', RealmPropertyType.double, mapTo: 'Length'),
      SchemaProperty('bpm', RealmPropertyType.double, mapTo: 'BPM'),
      SchemaProperty(
        'hash',
        RealmPropertyType.string,
        mapTo: 'Hash',
        optional: true,
      ),
      SchemaProperty(
        'starRating',
        RealmPropertyType.double,
        mapTo: 'StarRating',
      ),
      SchemaProperty(
        'md5Hash',
        RealmPropertyType.string,
        mapTo: 'MD5Hash',
        optional: true,
      ),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}

class BeatmapSetInfo extends _BeatmapSetInfo
    with RealmEntity, RealmObjectBase, RealmObject {
  BeatmapSetInfo(
    Uuid id,
    int onlineID,
    DateTime dateAdded,
    int status,
    bool deletePending,
    bool isProtected, {
    DateTime? dateSubmitted,
    String? hash,
    Iterable<BeatmapInfo> beatmaps = const [],
  }) {
    RealmObjectBase.set(this, 'ID', id);
    RealmObjectBase.set(this, 'OnlineID', onlineID);
    RealmObjectBase.set(this, 'DateAdded', dateAdded);
    RealmObjectBase.set(this, 'DateSubmitted', dateSubmitted);
    RealmObjectBase.set(this, 'Status', status);
    RealmObjectBase.set(this, 'DeletePending', deletePending);
    RealmObjectBase.set(this, 'Hash', hash);
    RealmObjectBase.set(this, 'Protected', isProtected);
    RealmObjectBase.set<RealmList<BeatmapInfo>>(
      this,
      'Beatmaps',
      RealmList<BeatmapInfo>(beatmaps),
    );
  }

  BeatmapSetInfo._();

  @override
  Uuid get id => RealmObjectBase.get<Uuid>(this, 'ID') as Uuid;
  @override
  set id(Uuid value) => RealmObjectBase.set(this, 'ID', value);

  @override
  int get onlineID => RealmObjectBase.get<int>(this, 'OnlineID') as int;
  @override
  set onlineID(int value) => RealmObjectBase.set(this, 'OnlineID', value);

  @override
  DateTime get dateAdded =>
      RealmObjectBase.get<DateTime>(this, 'DateAdded') as DateTime;
  @override
  set dateAdded(DateTime value) =>
      RealmObjectBase.set(this, 'DateAdded', value);

  @override
  DateTime? get dateSubmitted =>
      RealmObjectBase.get<DateTime>(this, 'DateSubmitted') as DateTime?;
  @override
  set dateSubmitted(DateTime? value) =>
      RealmObjectBase.set(this, 'DateSubmitted', value);

  @override
  int get status => RealmObjectBase.get<int>(this, 'Status') as int;
  @override
  set status(int value) => RealmObjectBase.set(this, 'Status', value);

  @override
  bool get deletePending =>
      RealmObjectBase.get<bool>(this, 'DeletePending') as bool;
  @override
  set deletePending(bool value) =>
      RealmObjectBase.set(this, 'DeletePending', value);

  @override
  String? get hash => RealmObjectBase.get<String>(this, 'Hash') as String?;
  @override
  set hash(String? value) => RealmObjectBase.set(this, 'Hash', value);

  @override
  bool get isProtected => RealmObjectBase.get<bool>(this, 'Protected') as bool;
  @override
  set isProtected(bool value) => RealmObjectBase.set(this, 'Protected', value);

  @override
  RealmList<BeatmapInfo> get beatmaps =>
      RealmObjectBase.get<BeatmapInfo>(this, 'Beatmaps')
          as RealmList<BeatmapInfo>;
  @override
  set beatmaps(covariant RealmList<BeatmapInfo> value) =>
      throw RealmUnsupportedSetError();

  @override
  Stream<RealmObjectChanges<BeatmapSetInfo>> get changes =>
      RealmObjectBase.getChanges<BeatmapSetInfo>(this);

  @override
  Stream<RealmObjectChanges<BeatmapSetInfo>> changesFor([
    List<String>? keyPaths,
  ]) => RealmObjectBase.getChangesFor<BeatmapSetInfo>(this, keyPaths);

  @override
  BeatmapSetInfo freeze() => RealmObjectBase.freezeObject<BeatmapSetInfo>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      'ID': id.toEJson(),
      'OnlineID': onlineID.toEJson(),
      'DateAdded': dateAdded.toEJson(),
      'DateSubmitted': dateSubmitted.toEJson(),
      'Status': status.toEJson(),
      'DeletePending': deletePending.toEJson(),
      'Hash': hash.toEJson(),
      'Protected': isProtected.toEJson(),
      'Beatmaps': beatmaps.toEJson(),
    };
  }

  static EJsonValue _toEJson(BeatmapSetInfo value) => value.toEJson();
  static BeatmapSetInfo _fromEJson(EJsonValue ejson) {
    if (ejson is! Map<String, dynamic>) return raiseInvalidEJson(ejson);
    return switch (ejson) {
      {
        'ID': EJsonValue id,
        'OnlineID': EJsonValue onlineID,
        'DateAdded': EJsonValue dateAdded,
        'Status': EJsonValue status,
        'DeletePending': EJsonValue deletePending,
        'Protected': EJsonValue isProtected,
      } =>
        BeatmapSetInfo(
          fromEJson(id),
          fromEJson(onlineID),
          fromEJson(dateAdded),
          fromEJson(status),
          fromEJson(deletePending),
          fromEJson(isProtected),
          dateSubmitted: fromEJson(ejson['DateSubmitted']),
          hash: fromEJson(ejson['Hash']),
          beatmaps: fromEJson(ejson['Beatmaps']),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(BeatmapSetInfo._);
    register(_toEJson, _fromEJson);
    return const SchemaObject(
      ObjectType.realmObject,
      BeatmapSetInfo,
      'BeatmapSet',
      [
        SchemaProperty(
          'id',
          RealmPropertyType.uuid,
          mapTo: 'ID',
          primaryKey: true,
        ),
        SchemaProperty('onlineID', RealmPropertyType.int, mapTo: 'OnlineID'),
        SchemaProperty(
          'dateAdded',
          RealmPropertyType.timestamp,
          mapTo: 'DateAdded',
        ),
        SchemaProperty(
          'dateSubmitted',
          RealmPropertyType.timestamp,
          mapTo: 'DateSubmitted',
          optional: true,
        ),
        SchemaProperty('status', RealmPropertyType.int, mapTo: 'Status'),
        SchemaProperty(
          'deletePending',
          RealmPropertyType.bool,
          mapTo: 'DeletePending',
        ),
        SchemaProperty(
          'hash',
          RealmPropertyType.string,
          mapTo: 'Hash',
          optional: true,
        ),
        SchemaProperty(
          'isProtected',
          RealmPropertyType.bool,
          mapTo: 'Protected',
        ),
        SchemaProperty(
          'beatmaps',
          RealmPropertyType.object,
          mapTo: 'Beatmaps',
          linkTarget: 'Beatmap',
          collectionType: RealmCollectionType.list,
        ),
      ],
    );
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
