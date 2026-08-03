// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ChannelsTable extends Channels with TableInfo<$ChannelsTable, Channel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
      'topic', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<int> cursor = GeneratedColumn<int>(
      'cursor', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastReadSeqMeta =
      const VerificationMeta('lastReadSeq');
  @override
  late final GeneratedColumn<int> lastReadSeq = GeneratedColumn<int>(
      'last_read_seq', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isPersonalSpaceMeta =
      const VerificationMeta('isPersonalSpace');
  @override
  late final GeneratedColumn<bool> isPersonalSpace = GeneratedColumn<bool>(
      'is_personal_space', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_personal_space" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _dmParticipantIdMeta =
      const VerificationMeta('dmParticipantId');
  @override
  late final GeneratedColumn<String> dmParticipantId = GeneratedColumn<String>(
      'dm_participant_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _opCursorMeta =
      const VerificationMeta('opCursor');
  @override
  late final GeneratedColumn<int> opCursor = GeneratedColumn<int>(
      'op_cursor', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _parentMessageIdMeta =
      const VerificationMeta('parentMessageId');
  @override
  late final GeneratedColumn<String> parentMessageId = GeneratedColumn<String>(
      'parent_message_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        kind,
        createdAt,
        topic,
        cursor,
        lastReadSeq,
        isPersonalSpace,
        dmParticipantId,
        position,
        opCursor,
        parentMessageId,
        categoryId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  VerificationContext validateIntegrity(Insertable<Channel> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
          _topicMeta, topic.isAcceptableOrUnknown(data['topic']!, _topicMeta));
    }
    if (data.containsKey('cursor')) {
      context.handle(_cursorMeta,
          cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta));
    }
    if (data.containsKey('last_read_seq')) {
      context.handle(
          _lastReadSeqMeta,
          lastReadSeq.isAcceptableOrUnknown(
              data['last_read_seq']!, _lastReadSeqMeta));
    }
    if (data.containsKey('is_personal_space')) {
      context.handle(
          _isPersonalSpaceMeta,
          isPersonalSpace.isAcceptableOrUnknown(
              data['is_personal_space']!, _isPersonalSpaceMeta));
    }
    if (data.containsKey('dm_participant_id')) {
      context.handle(
          _dmParticipantIdMeta,
          dmParticipantId.isAcceptableOrUnknown(
              data['dm_participant_id']!, _dmParticipantIdMeta));
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    }
    if (data.containsKey('op_cursor')) {
      context.handle(_opCursorMeta,
          opCursor.isAcceptableOrUnknown(data['op_cursor']!, _opCursorMeta));
    }
    if (data.containsKey('parent_message_id')) {
      context.handle(
          _parentMessageIdMeta,
          parentMessageId.isAcceptableOrUnknown(
              data['parent_message_id']!, _parentMessageIdMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Channel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Channel(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      topic: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}topic']),
      cursor: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cursor'])!,
      lastReadSeq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_read_seq'])!,
      isPersonalSpace: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}is_personal_space'])!,
      dmParticipantId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}dm_participant_id']),
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
      opCursor: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}op_cursor']),
      parentMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}parent_message_id']),
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id']),
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }
}

class Channel extends DataClass implements Insertable<Channel> {
  final String id;
  final String name;
  final String kind;
  final int createdAt;

  /// A one-line header shown beside the name. Null for no topic.
  final String? topic;

  /// The highest `seq` this client holds for the channel: the sync cursor.
  final int cursor;

  /// How far the user has read, mirrored from the server.
  final int lastReadSeq;

  /// Whether this is the caller's own personal space, set only by
  /// `channelFromDm` from `dm.user.id == selfId` - never from `name`, which
  /// is a display string another member's own display name can collide with.
  final bool isPersonalSpace;

  /// The other user in this DM, set only by `channelFromDm`. Null for a
  /// non-DM channel, and for a DM row cached before this column existed
  /// until the next channel refresh replaces it.
  final String? dmParticipantId;

  /// Sort key among the deployment's live, non-DM channels: lower sorts
  /// first, mirroring the server's `channels.position`. Deployment-wide, set
  /// by a manager's drag, not a per-device preference. Meaningless for a DM,
  /// which is never reordered by it.
  final int position;

  /// The highest message-op `seq` this client has applied for the channel.
  ///
  /// Nullable, and the nullability is the whole mechanism: null means "I hold
  /// no op cursor, adopt whatever head the next response reports", and there
  /// is no in-band integer that could mean that. Zero means "I am caught up
  /// with a stream that has never had an op", which is a different claim.
  /// A reset clears it back to null rather than lowering it to zero, or the
  /// client asks from 0 forever against a server that has swept.
  final int? opCursor;

  /// The message this channel is a thread of, or null for an ordinary
  /// channel. Set only by [MessageStore.upsertChannels]'s callers when they
  /// already hold an `api.Channel` carrying it - see
  /// `providers/threads.dart`. Never used to derive [kind] or overwrites;
  /// it exists locally only so a thread row can be told apart from an
  /// ordinary one when deciding what the rail shows and what a full channel
  /// refresh may prune.
  final String? parentMessageId;

  /// The rail section this channel is filed under, or null for
  /// uncategorised. Decides placement only, mirroring the server's
  /// `channels.category_id` - see docs/decisions/0006-channel-categories.md.
  /// Not a foreign key here: [ChannelCategories] is replaced on its own path
  /// ([MessageStore.replaceCategories]), never joined against this table for
  /// referential integrity, the same reason `dmParticipantId` names a user
  /// id with no local `Users` table to reference.
  final String? categoryId;
  const Channel(
      {required this.id,
      required this.name,
      required this.kind,
      required this.createdAt,
      this.topic,
      required this.cursor,
      required this.lastReadSeq,
      required this.isPersonalSpace,
      this.dmParticipantId,
      required this.position,
      this.opCursor,
      this.parentMessageId,
      this.categoryId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || topic != null) {
      map['topic'] = Variable<String>(topic);
    }
    map['cursor'] = Variable<int>(cursor);
    map['last_read_seq'] = Variable<int>(lastReadSeq);
    map['is_personal_space'] = Variable<bool>(isPersonalSpace);
    if (!nullToAbsent || dmParticipantId != null) {
      map['dm_participant_id'] = Variable<String>(dmParticipantId);
    }
    map['position'] = Variable<int>(position);
    if (!nullToAbsent || opCursor != null) {
      map['op_cursor'] = Variable<int>(opCursor);
    }
    if (!nullToAbsent || parentMessageId != null) {
      map['parent_message_id'] = Variable<String>(parentMessageId);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      createdAt: Value(createdAt),
      topic:
          topic == null && nullToAbsent ? const Value.absent() : Value(topic),
      cursor: Value(cursor),
      lastReadSeq: Value(lastReadSeq),
      isPersonalSpace: Value(isPersonalSpace),
      dmParticipantId: dmParticipantId == null && nullToAbsent
          ? const Value.absent()
          : Value(dmParticipantId),
      position: Value(position),
      opCursor: opCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(opCursor),
      parentMessageId: parentMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentMessageId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
    );
  }

  factory Channel.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Channel(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      topic: serializer.fromJson<String?>(json['topic']),
      cursor: serializer.fromJson<int>(json['cursor']),
      lastReadSeq: serializer.fromJson<int>(json['lastReadSeq']),
      isPersonalSpace: serializer.fromJson<bool>(json['isPersonalSpace']),
      dmParticipantId: serializer.fromJson<String?>(json['dmParticipantId']),
      position: serializer.fromJson<int>(json['position']),
      opCursor: serializer.fromJson<int?>(json['opCursor']),
      parentMessageId: serializer.fromJson<String?>(json['parentMessageId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'createdAt': serializer.toJson<int>(createdAt),
      'topic': serializer.toJson<String?>(topic),
      'cursor': serializer.toJson<int>(cursor),
      'lastReadSeq': serializer.toJson<int>(lastReadSeq),
      'isPersonalSpace': serializer.toJson<bool>(isPersonalSpace),
      'dmParticipantId': serializer.toJson<String?>(dmParticipantId),
      'position': serializer.toJson<int>(position),
      'opCursor': serializer.toJson<int?>(opCursor),
      'parentMessageId': serializer.toJson<String?>(parentMessageId),
      'categoryId': serializer.toJson<String?>(categoryId),
    };
  }

  Channel copyWith(
          {String? id,
          String? name,
          String? kind,
          int? createdAt,
          Value<String?> topic = const Value.absent(),
          int? cursor,
          int? lastReadSeq,
          bool? isPersonalSpace,
          Value<String?> dmParticipantId = const Value.absent(),
          int? position,
          Value<int?> opCursor = const Value.absent(),
          Value<String?> parentMessageId = const Value.absent(),
          Value<String?> categoryId = const Value.absent()}) =>
      Channel(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        createdAt: createdAt ?? this.createdAt,
        topic: topic.present ? topic.value : this.topic,
        cursor: cursor ?? this.cursor,
        lastReadSeq: lastReadSeq ?? this.lastReadSeq,
        isPersonalSpace: isPersonalSpace ?? this.isPersonalSpace,
        dmParticipantId: dmParticipantId.present
            ? dmParticipantId.value
            : this.dmParticipantId,
        position: position ?? this.position,
        opCursor: opCursor.present ? opCursor.value : this.opCursor,
        parentMessageId: parentMessageId.present
            ? parentMessageId.value
            : this.parentMessageId,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
      );
  Channel copyWithCompanion(ChannelsCompanion data) {
    return Channel(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      topic: data.topic.present ? data.topic.value : this.topic,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      lastReadSeq:
          data.lastReadSeq.present ? data.lastReadSeq.value : this.lastReadSeq,
      isPersonalSpace: data.isPersonalSpace.present
          ? data.isPersonalSpace.value
          : this.isPersonalSpace,
      dmParticipantId: data.dmParticipantId.present
          ? data.dmParticipantId.value
          : this.dmParticipantId,
      position: data.position.present ? data.position.value : this.position,
      opCursor: data.opCursor.present ? data.opCursor.value : this.opCursor,
      parentMessageId: data.parentMessageId.present
          ? data.parentMessageId.value
          : this.parentMessageId,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Channel(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt, ')
          ..write('topic: $topic, ')
          ..write('cursor: $cursor, ')
          ..write('lastReadSeq: $lastReadSeq, ')
          ..write('isPersonalSpace: $isPersonalSpace, ')
          ..write('dmParticipantId: $dmParticipantId, ')
          ..write('position: $position, ')
          ..write('opCursor: $opCursor, ')
          ..write('parentMessageId: $parentMessageId, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      kind,
      createdAt,
      topic,
      cursor,
      lastReadSeq,
      isPersonalSpace,
      dmParticipantId,
      position,
      opCursor,
      parentMessageId,
      categoryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Channel &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.createdAt == this.createdAt &&
          other.topic == this.topic &&
          other.cursor == this.cursor &&
          other.lastReadSeq == this.lastReadSeq &&
          other.isPersonalSpace == this.isPersonalSpace &&
          other.dmParticipantId == this.dmParticipantId &&
          other.position == this.position &&
          other.opCursor == this.opCursor &&
          other.parentMessageId == this.parentMessageId &&
          other.categoryId == this.categoryId);
}

class ChannelsCompanion extends UpdateCompanion<Channel> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<int> createdAt;
  final Value<String?> topic;
  final Value<int> cursor;
  final Value<int> lastReadSeq;
  final Value<bool> isPersonalSpace;
  final Value<String?> dmParticipantId;
  final Value<int> position;
  final Value<int?> opCursor;
  final Value<String?> parentMessageId;
  final Value<String?> categoryId;
  final Value<int> rowid;
  const ChannelsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.topic = const Value.absent(),
    this.cursor = const Value.absent(),
    this.lastReadSeq = const Value.absent(),
    this.isPersonalSpace = const Value.absent(),
    this.dmParticipantId = const Value.absent(),
    this.position = const Value.absent(),
    this.opCursor = const Value.absent(),
    this.parentMessageId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelsCompanion.insert({
    required String id,
    required String name,
    required String kind,
    required int createdAt,
    this.topic = const Value.absent(),
    this.cursor = const Value.absent(),
    this.lastReadSeq = const Value.absent(),
    this.isPersonalSpace = const Value.absent(),
    this.dmParticipantId = const Value.absent(),
    this.position = const Value.absent(),
    this.opCursor = const Value.absent(),
    this.parentMessageId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        kind = Value(kind),
        createdAt = Value(createdAt);
  static Insertable<Channel> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<int>? createdAt,
    Expression<String>? topic,
    Expression<int>? cursor,
    Expression<int>? lastReadSeq,
    Expression<bool>? isPersonalSpace,
    Expression<String>? dmParticipantId,
    Expression<int>? position,
    Expression<int>? opCursor,
    Expression<String>? parentMessageId,
    Expression<String>? categoryId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (createdAt != null) 'created_at': createdAt,
      if (topic != null) 'topic': topic,
      if (cursor != null) 'cursor': cursor,
      if (lastReadSeq != null) 'last_read_seq': lastReadSeq,
      if (isPersonalSpace != null) 'is_personal_space': isPersonalSpace,
      if (dmParticipantId != null) 'dm_participant_id': dmParticipantId,
      if (position != null) 'position': position,
      if (opCursor != null) 'op_cursor': opCursor,
      if (parentMessageId != null) 'parent_message_id': parentMessageId,
      if (categoryId != null) 'category_id': categoryId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? kind,
      Value<int>? createdAt,
      Value<String?>? topic,
      Value<int>? cursor,
      Value<int>? lastReadSeq,
      Value<bool>? isPersonalSpace,
      Value<String?>? dmParticipantId,
      Value<int>? position,
      Value<int?>? opCursor,
      Value<String?>? parentMessageId,
      Value<String?>? categoryId,
      Value<int>? rowid}) {
    return ChannelsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      topic: topic ?? this.topic,
      cursor: cursor ?? this.cursor,
      lastReadSeq: lastReadSeq ?? this.lastReadSeq,
      isPersonalSpace: isPersonalSpace ?? this.isPersonalSpace,
      dmParticipantId: dmParticipantId ?? this.dmParticipantId,
      position: position ?? this.position,
      opCursor: opCursor ?? this.opCursor,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      categoryId: categoryId ?? this.categoryId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<int>(cursor.value);
    }
    if (lastReadSeq.present) {
      map['last_read_seq'] = Variable<int>(lastReadSeq.value);
    }
    if (isPersonalSpace.present) {
      map['is_personal_space'] = Variable<bool>(isPersonalSpace.value);
    }
    if (dmParticipantId.present) {
      map['dm_participant_id'] = Variable<String>(dmParticipantId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (opCursor.present) {
      map['op_cursor'] = Variable<int>(opCursor.value);
    }
    if (parentMessageId.present) {
      map['parent_message_id'] = Variable<String>(parentMessageId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt, ')
          ..write('topic: $topic, ')
          ..write('cursor: $cursor, ')
          ..write('lastReadSeq: $lastReadSeq, ')
          ..write('isPersonalSpace: $isPersonalSpace, ')
          ..write('dmParticipantId: $dmParticipantId, ')
          ..write('position: $position, ')
          ..write('opCursor: $opCursor, ')
          ..write('parentMessageId: $parentMessageId, ')
          ..write('categoryId: $categoryId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _channelIdMeta =
      const VerificationMeta('channelId');
  @override
  late final GeneratedColumn<String> channelId = GeneratedColumn<String>(
      'channel_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorIdMeta =
      const VerificationMeta('authorId');
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
      'author_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _authorDisplayNameMeta =
      const VerificationMeta('authorDisplayName');
  @override
  late final GeneratedColumn<String> authorDisplayName =
      GeneratedColumn<String>('author_display_name', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _editedAtMeta =
      const VerificationMeta('editedAt');
  @override
  late final GeneratedColumn<int> editedAt = GeneratedColumn<int>(
      'edited_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _replyToIdMeta =
      const VerificationMeta('replyToId');
  @override
  late final GeneratedColumn<String> replyToId = GeneratedColumn<String>(
      'reply_to_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pendingMeta =
      const VerificationMeta('pending');
  @override
  late final GeneratedColumn<bool> pending = GeneratedColumn<bool>(
      'pending', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("pending" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _failedMeta = const VerificationMeta('failed');
  @override
  late final GeneratedColumn<bool> failed = GeneratedColumn<bool>(
      'failed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("failed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _failureReasonMeta =
      const VerificationMeta('failureReason');
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
      'failure_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        channelId,
        authorId,
        authorDisplayName,
        seq,
        content,
        createdAt,
        editedAt,
        replyToId,
        pending,
        failed,
        failureReason
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('channel_id')) {
      context.handle(_channelIdMeta,
          channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta));
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(_authorIdMeta,
          authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta));
    }
    if (data.containsKey('author_display_name')) {
      context.handle(
          _authorDisplayNameMeta,
          authorDisplayName.isAcceptableOrUnknown(
              data['author_display_name']!, _authorDisplayNameMeta));
    }
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('edited_at')) {
      context.handle(_editedAtMeta,
          editedAt.isAcceptableOrUnknown(data['edited_at']!, _editedAtMeta));
    }
    if (data.containsKey('reply_to_id')) {
      context.handle(
          _replyToIdMeta,
          replyToId.isAcceptableOrUnknown(
              data['reply_to_id']!, _replyToIdMeta));
    }
    if (data.containsKey('pending')) {
      context.handle(_pendingMeta,
          pending.isAcceptableOrUnknown(data['pending']!, _pendingMeta));
    }
    if (data.containsKey('failed')) {
      context.handle(_failedMeta,
          failed.isAcceptableOrUnknown(data['failed']!, _failedMeta));
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
          _failureReasonMeta,
          failureReason.isAcceptableOrUnknown(
              data['failure_reason']!, _failureReasonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      channelId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}channel_id'])!,
      authorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author_id']),
      authorDisplayName: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}author_display_name']),
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      editedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}edited_at']),
      replyToId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reply_to_id']),
      pending: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}pending'])!,
      failed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}failed'])!,
      failureReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}failure_reason']),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String channelId;
  final String? authorId;

  /// Sent with the message so rendering a channel needs no lookup per sender.
  /// Null when the author was anonymized, exactly as [authorId] is.
  final String? authorDisplayName;

  /// Server order key. Zero while a message is only local (an optimistic echo
  /// that has not been acknowledged yet), so pending messages sort last.
  final int seq;
  final String content;
  final int createdAt;
  final int? editedAt;

  /// The message this one replies to, or null. Only ever the id: the
  /// parent's own content, author and liveness are read by looking that id
  /// up in this same table, never copied onto this row - there is nothing
  /// here for an edit or delete of the parent to leave stale.
  final String? replyToId;

  /// True while the send is in flight. The UI shows these differently and they
  /// are replaced in place by the server's copy on acknowledgement.
  final bool pending;

  /// True when the send failed and the user can retry it.
  final bool failed;

  /// Why [failed] is true, in the server's own words (its `error` body, or a
  /// transport failure's own message) - never a generic "send failed" with
  /// nothing behind it. Null whenever [failed] is false.
  final String? failureReason;
  const Message(
      {required this.id,
      required this.channelId,
      this.authorId,
      this.authorDisplayName,
      required this.seq,
      required this.content,
      required this.createdAt,
      this.editedAt,
      this.replyToId,
      required this.pending,
      required this.failed,
      this.failureReason});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['channel_id'] = Variable<String>(channelId);
    if (!nullToAbsent || authorId != null) {
      map['author_id'] = Variable<String>(authorId);
    }
    if (!nullToAbsent || authorDisplayName != null) {
      map['author_display_name'] = Variable<String>(authorDisplayName);
    }
    map['seq'] = Variable<int>(seq);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || editedAt != null) {
      map['edited_at'] = Variable<int>(editedAt);
    }
    if (!nullToAbsent || replyToId != null) {
      map['reply_to_id'] = Variable<String>(replyToId);
    }
    map['pending'] = Variable<bool>(pending);
    map['failed'] = Variable<bool>(failed);
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      channelId: Value(channelId),
      authorId: authorId == null && nullToAbsent
          ? const Value.absent()
          : Value(authorId),
      authorDisplayName: authorDisplayName == null && nullToAbsent
          ? const Value.absent()
          : Value(authorDisplayName),
      seq: Value(seq),
      content: Value(content),
      createdAt: Value(createdAt),
      editedAt: editedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(editedAt),
      replyToId: replyToId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToId),
      pending: Value(pending),
      failed: Value(failed),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      channelId: serializer.fromJson<String>(json['channelId']),
      authorId: serializer.fromJson<String?>(json['authorId']),
      authorDisplayName:
          serializer.fromJson<String?>(json['authorDisplayName']),
      seq: serializer.fromJson<int>(json['seq']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      editedAt: serializer.fromJson<int?>(json['editedAt']),
      replyToId: serializer.fromJson<String?>(json['replyToId']),
      pending: serializer.fromJson<bool>(json['pending']),
      failed: serializer.fromJson<bool>(json['failed']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'channelId': serializer.toJson<String>(channelId),
      'authorId': serializer.toJson<String?>(authorId),
      'authorDisplayName': serializer.toJson<String?>(authorDisplayName),
      'seq': serializer.toJson<int>(seq),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<int>(createdAt),
      'editedAt': serializer.toJson<int?>(editedAt),
      'replyToId': serializer.toJson<String?>(replyToId),
      'pending': serializer.toJson<bool>(pending),
      'failed': serializer.toJson<bool>(failed),
      'failureReason': serializer.toJson<String?>(failureReason),
    };
  }

  Message copyWith(
          {String? id,
          String? channelId,
          Value<String?> authorId = const Value.absent(),
          Value<String?> authorDisplayName = const Value.absent(),
          int? seq,
          String? content,
          int? createdAt,
          Value<int?> editedAt = const Value.absent(),
          Value<String?> replyToId = const Value.absent(),
          bool? pending,
          bool? failed,
          Value<String?> failureReason = const Value.absent()}) =>
      Message(
        id: id ?? this.id,
        channelId: channelId ?? this.channelId,
        authorId: authorId.present ? authorId.value : this.authorId,
        authorDisplayName: authorDisplayName.present
            ? authorDisplayName.value
            : this.authorDisplayName,
        seq: seq ?? this.seq,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        editedAt: editedAt.present ? editedAt.value : this.editedAt,
        replyToId: replyToId.present ? replyToId.value : this.replyToId,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        failureReason:
            failureReason.present ? failureReason.value : this.failureReason,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      authorDisplayName: data.authorDisplayName.present
          ? data.authorDisplayName.value
          : this.authorDisplayName,
      seq: data.seq.present ? data.seq.value : this.seq,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      editedAt: data.editedAt.present ? data.editedAt.value : this.editedAt,
      replyToId: data.replyToId.present ? data.replyToId.value : this.replyToId,
      pending: data.pending.present ? data.pending.value : this.pending,
      failed: data.failed.present ? data.failed.value : this.failed,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('channelId: $channelId, ')
          ..write('authorId: $authorId, ')
          ..write('authorDisplayName: $authorDisplayName, ')
          ..write('seq: $seq, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('editedAt: $editedAt, ')
          ..write('replyToId: $replyToId, ')
          ..write('pending: $pending, ')
          ..write('failed: $failed, ')
          ..write('failureReason: $failureReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      channelId,
      authorId,
      authorDisplayName,
      seq,
      content,
      createdAt,
      editedAt,
      replyToId,
      pending,
      failed,
      failureReason);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.channelId == this.channelId &&
          other.authorId == this.authorId &&
          other.authorDisplayName == this.authorDisplayName &&
          other.seq == this.seq &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.editedAt == this.editedAt &&
          other.replyToId == this.replyToId &&
          other.pending == this.pending &&
          other.failed == this.failed &&
          other.failureReason == this.failureReason);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> channelId;
  final Value<String?> authorId;
  final Value<String?> authorDisplayName;
  final Value<int> seq;
  final Value<String> content;
  final Value<int> createdAt;
  final Value<int?> editedAt;
  final Value<String?> replyToId;
  final Value<bool> pending;
  final Value<bool> failed;
  final Value<String?> failureReason;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.channelId = const Value.absent(),
    this.authorId = const Value.absent(),
    this.authorDisplayName = const Value.absent(),
    this.seq = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.editedAt = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.pending = const Value.absent(),
    this.failed = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String channelId,
    this.authorId = const Value.absent(),
    this.authorDisplayName = const Value.absent(),
    this.seq = const Value.absent(),
    required String content,
    required int createdAt,
    this.editedAt = const Value.absent(),
    this.replyToId = const Value.absent(),
    this.pending = const Value.absent(),
    this.failed = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        channelId = Value(channelId),
        content = Value(content),
        createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? channelId,
    Expression<String>? authorId,
    Expression<String>? authorDisplayName,
    Expression<int>? seq,
    Expression<String>? content,
    Expression<int>? createdAt,
    Expression<int>? editedAt,
    Expression<String>? replyToId,
    Expression<bool>? pending,
    Expression<bool>? failed,
    Expression<String>? failureReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (channelId != null) 'channel_id': channelId,
      if (authorId != null) 'author_id': authorId,
      if (authorDisplayName != null) 'author_display_name': authorDisplayName,
      if (seq != null) 'seq': seq,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (editedAt != null) 'edited_at': editedAt,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (pending != null) 'pending': pending,
      if (failed != null) 'failed': failed,
      if (failureReason != null) 'failure_reason': failureReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? channelId,
      Value<String?>? authorId,
      Value<String?>? authorDisplayName,
      Value<int>? seq,
      Value<String>? content,
      Value<int>? createdAt,
      Value<int?>? editedAt,
      Value<String?>? replyToId,
      Value<bool>? pending,
      Value<bool>? failed,
      Value<String?>? failureReason,
      Value<int>? rowid}) {
    return MessagesCompanion(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      authorId: authorId ?? this.authorId,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      seq: seq ?? this.seq,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      replyToId: replyToId ?? this.replyToId,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
      failureReason: failureReason ?? this.failureReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<String>(channelId.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (authorDisplayName.present) {
      map['author_display_name'] = Variable<String>(authorDisplayName.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (editedAt.present) {
      map['edited_at'] = Variable<int>(editedAt.value);
    }
    if (replyToId.present) {
      map['reply_to_id'] = Variable<String>(replyToId.value);
    }
    if (pending.present) {
      map['pending'] = Variable<bool>(pending.value);
    }
    if (failed.present) {
      map['failed'] = Variable<bool>(failed.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('channelId: $channelId, ')
          ..write('authorId: $authorId, ')
          ..write('authorDisplayName: $authorDisplayName, ')
          ..write('seq: $seq, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('editedAt: $editedAt, ')
          ..write('replyToId: $replyToId, ')
          ..write('pending: $pending, ')
          ..write('failed: $failed, ')
          ..write('failureReason: $failureReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelCategoriesTable extends ChannelCategories
    with TableInfo<$ChannelCategoriesTable, ChannelCategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [id, name, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channel_categories';
  @override
  VerificationContext validateIntegrity(Insertable<ChannelCategoryRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChannelCategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelCategoryRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
    );
  }

  @override
  $ChannelCategoriesTable createAlias(String alias) {
    return $ChannelCategoriesTable(attachedDatabase, alias);
  }
}

class ChannelCategoryRow extends DataClass
    implements Insertable<ChannelCategoryRow> {
  final String id;
  final String name;

  /// Sort key among the deployment's live categories: lower sorts first.
  final int position;
  const ChannelCategoryRow(
      {required this.id, required this.name, required this.position});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['position'] = Variable<int>(position);
    return map;
  }

  ChannelCategoriesCompanion toCompanion(bool nullToAbsent) {
    return ChannelCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      position: Value(position),
    );
  }

  factory ChannelCategoryRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelCategoryRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<int>(position),
    };
  }

  ChannelCategoryRow copyWith({String? id, String? name, int? position}) =>
      ChannelCategoryRow(
        id: id ?? this.id,
        name: name ?? this.name,
        position: position ?? this.position,
      );
  ChannelCategoryRow copyWithCompanion(ChannelCategoriesCompanion data) {
    return ChannelCategoryRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelCategoryRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelCategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.position == this.position);
}

class ChannelCategoriesCompanion extends UpdateCompanion<ChannelCategoryRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> position;
  final Value<int> rowid;
  const ChannelCategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelCategoriesCompanion.insert({
    required String id,
    required String name,
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<ChannelCategoryRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelCategoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? position,
      Value<int>? rowid}) {
    return ChannelCategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SlimmDatabase extends GeneratedDatabase {
  _$SlimmDatabase(QueryExecutor e) : super(e);
  $SlimmDatabaseManager get managers => $SlimmDatabaseManager(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $ChannelCategoriesTable channelCategories =
      $ChannelCategoriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [channels, messages, channelCategories];
}

typedef $$ChannelsTableCreateCompanionBuilder = ChannelsCompanion Function({
  required String id,
  required String name,
  required String kind,
  required int createdAt,
  Value<String?> topic,
  Value<int> cursor,
  Value<int> lastReadSeq,
  Value<bool> isPersonalSpace,
  Value<String?> dmParticipantId,
  Value<int> position,
  Value<int?> opCursor,
  Value<String?> parentMessageId,
  Value<String?> categoryId,
  Value<int> rowid,
});
typedef $$ChannelsTableUpdateCompanionBuilder = ChannelsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> kind,
  Value<int> createdAt,
  Value<String?> topic,
  Value<int> cursor,
  Value<int> lastReadSeq,
  Value<bool> isPersonalSpace,
  Value<String?> dmParticipantId,
  Value<int> position,
  Value<int?> opCursor,
  Value<String?> parentMessageId,
  Value<String?> categoryId,
  Value<int> rowid,
});

class $$ChannelsTableFilterComposer
    extends Composer<_$SlimmDatabase, $ChannelsTable> {
  $$ChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cursor => $composableBuilder(
      column: $table.cursor, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastReadSeq => $composableBuilder(
      column: $table.lastReadSeq, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPersonalSpace => $composableBuilder(
      column: $table.isPersonalSpace,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dmParticipantId => $composableBuilder(
      column: $table.dmParticipantId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get opCursor => $composableBuilder(
      column: $table.opCursor, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentMessageId => $composableBuilder(
      column: $table.parentMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));
}

class $$ChannelsTableOrderingComposer
    extends Composer<_$SlimmDatabase, $ChannelsTable> {
  $$ChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get topic => $composableBuilder(
      column: $table.topic, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cursor => $composableBuilder(
      column: $table.cursor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastReadSeq => $composableBuilder(
      column: $table.lastReadSeq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPersonalSpace => $composableBuilder(
      column: $table.isPersonalSpace,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dmParticipantId => $composableBuilder(
      column: $table.dmParticipantId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get opCursor => $composableBuilder(
      column: $table.opCursor, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentMessageId => $composableBuilder(
      column: $table.parentMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));
}

class $$ChannelsTableAnnotationComposer
    extends Composer<_$SlimmDatabase, $ChannelsTable> {
  $$ChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<int> get lastReadSeq => $composableBuilder(
      column: $table.lastReadSeq, builder: (column) => column);

  GeneratedColumn<bool> get isPersonalSpace => $composableBuilder(
      column: $table.isPersonalSpace, builder: (column) => column);

  GeneratedColumn<String> get dmParticipantId => $composableBuilder(
      column: $table.dmParticipantId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get opCursor =>
      $composableBuilder(column: $table.opCursor, builder: (column) => column);

  GeneratedColumn<String> get parentMessageId => $composableBuilder(
      column: $table.parentMessageId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);
}

class $$ChannelsTableTableManager extends RootTableManager<
    _$SlimmDatabase,
    $ChannelsTable,
    Channel,
    $$ChannelsTableFilterComposer,
    $$ChannelsTableOrderingComposer,
    $$ChannelsTableAnnotationComposer,
    $$ChannelsTableCreateCompanionBuilder,
    $$ChannelsTableUpdateCompanionBuilder,
    (Channel, BaseReferences<_$SlimmDatabase, $ChannelsTable, Channel>),
    Channel,
    PrefetchHooks Function()> {
  $$ChannelsTableTableManager(_$SlimmDatabase db, $ChannelsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<String?> topic = const Value.absent(),
            Value<int> cursor = const Value.absent(),
            Value<int> lastReadSeq = const Value.absent(),
            Value<bool> isPersonalSpace = const Value.absent(),
            Value<String?> dmParticipantId = const Value.absent(),
            Value<int> position = const Value.absent(),
            Value<int?> opCursor = const Value.absent(),
            Value<String?> parentMessageId = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChannelsCompanion(
            id: id,
            name: name,
            kind: kind,
            createdAt: createdAt,
            topic: topic,
            cursor: cursor,
            lastReadSeq: lastReadSeq,
            isPersonalSpace: isPersonalSpace,
            dmParticipantId: dmParticipantId,
            position: position,
            opCursor: opCursor,
            parentMessageId: parentMessageId,
            categoryId: categoryId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String kind,
            required int createdAt,
            Value<String?> topic = const Value.absent(),
            Value<int> cursor = const Value.absent(),
            Value<int> lastReadSeq = const Value.absent(),
            Value<bool> isPersonalSpace = const Value.absent(),
            Value<String?> dmParticipantId = const Value.absent(),
            Value<int> position = const Value.absent(),
            Value<int?> opCursor = const Value.absent(),
            Value<String?> parentMessageId = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChannelsCompanion.insert(
            id: id,
            name: name,
            kind: kind,
            createdAt: createdAt,
            topic: topic,
            cursor: cursor,
            lastReadSeq: lastReadSeq,
            isPersonalSpace: isPersonalSpace,
            dmParticipantId: dmParticipantId,
            position: position,
            opCursor: opCursor,
            parentMessageId: parentMessageId,
            categoryId: categoryId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChannelsTableProcessedTableManager = ProcessedTableManager<
    _$SlimmDatabase,
    $ChannelsTable,
    Channel,
    $$ChannelsTableFilterComposer,
    $$ChannelsTableOrderingComposer,
    $$ChannelsTableAnnotationComposer,
    $$ChannelsTableCreateCompanionBuilder,
    $$ChannelsTableUpdateCompanionBuilder,
    (Channel, BaseReferences<_$SlimmDatabase, $ChannelsTable, Channel>),
    Channel,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String channelId,
  Value<String?> authorId,
  Value<String?> authorDisplayName,
  Value<int> seq,
  required String content,
  required int createdAt,
  Value<int?> editedAt,
  Value<String?> replyToId,
  Value<bool> pending,
  Value<bool> failed,
  Value<String?> failureReason,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> channelId,
  Value<String?> authorId,
  Value<String?> authorDisplayName,
  Value<int> seq,
  Value<String> content,
  Value<int> createdAt,
  Value<int?> editedAt,
  Value<String?> replyToId,
  Value<bool> pending,
  Value<bool> failed,
  Value<String?> failureReason,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer
    extends Composer<_$SlimmDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get channelId => $composableBuilder(
      column: $table.channelId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get authorId => $composableBuilder(
      column: $table.authorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get authorDisplayName => $composableBuilder(
      column: $table.authorDisplayName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get editedAt => $composableBuilder(
      column: $table.editedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToId => $composableBuilder(
      column: $table.replyToId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get pending => $composableBuilder(
      column: $table.pending, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get failed => $composableBuilder(
      column: $table.failed, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get failureReason => $composableBuilder(
      column: $table.failureReason, builder: (column) => ColumnFilters(column));
}

class $$MessagesTableOrderingComposer
    extends Composer<_$SlimmDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get channelId => $composableBuilder(
      column: $table.channelId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get authorId => $composableBuilder(
      column: $table.authorId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get authorDisplayName => $composableBuilder(
      column: $table.authorDisplayName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get editedAt => $composableBuilder(
      column: $table.editedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToId => $composableBuilder(
      column: $table.replyToId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get pending => $composableBuilder(
      column: $table.pending, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get failed => $composableBuilder(
      column: $table.failed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get failureReason => $composableBuilder(
      column: $table.failureReason,
      builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$SlimmDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get channelId =>
      $composableBuilder(column: $table.channelId, builder: (column) => column);

  GeneratedColumn<String> get authorId =>
      $composableBuilder(column: $table.authorId, builder: (column) => column);

  GeneratedColumn<String> get authorDisplayName => $composableBuilder(
      column: $table.authorDisplayName, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => column);

  GeneratedColumn<String> get replyToId =>
      $composableBuilder(column: $table.replyToId, builder: (column) => column);

  GeneratedColumn<bool> get pending =>
      $composableBuilder(column: $table.pending, builder: (column) => column);

  GeneratedColumn<bool> get failed =>
      $composableBuilder(column: $table.failed, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
      column: $table.failureReason, builder: (column) => column);
}

class $$MessagesTableTableManager extends RootTableManager<
    _$SlimmDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$SlimmDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()> {
  $$MessagesTableTableManager(_$SlimmDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> channelId = const Value.absent(),
            Value<String?> authorId = const Value.absent(),
            Value<String?> authorDisplayName = const Value.absent(),
            Value<int> seq = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int?> editedAt = const Value.absent(),
            Value<String?> replyToId = const Value.absent(),
            Value<bool> pending = const Value.absent(),
            Value<bool> failed = const Value.absent(),
            Value<String?> failureReason = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            channelId: channelId,
            authorId: authorId,
            authorDisplayName: authorDisplayName,
            seq: seq,
            content: content,
            createdAt: createdAt,
            editedAt: editedAt,
            replyToId: replyToId,
            pending: pending,
            failed: failed,
            failureReason: failureReason,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String channelId,
            Value<String?> authorId = const Value.absent(),
            Value<String?> authorDisplayName = const Value.absent(),
            Value<int> seq = const Value.absent(),
            required String content,
            required int createdAt,
            Value<int?> editedAt = const Value.absent(),
            Value<String?> replyToId = const Value.absent(),
            Value<bool> pending = const Value.absent(),
            Value<bool> failed = const Value.absent(),
            Value<String?> failureReason = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            channelId: channelId,
            authorId: authorId,
            authorDisplayName: authorDisplayName,
            seq: seq,
            content: content,
            createdAt: createdAt,
            editedAt: editedAt,
            replyToId: replyToId,
            pending: pending,
            failed: failed,
            failureReason: failureReason,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$SlimmDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$SlimmDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()>;
typedef $$ChannelCategoriesTableCreateCompanionBuilder
    = ChannelCategoriesCompanion Function({
  required String id,
  required String name,
  Value<int> position,
  Value<int> rowid,
});
typedef $$ChannelCategoriesTableUpdateCompanionBuilder
    = ChannelCategoriesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> position,
  Value<int> rowid,
});

class $$ChannelCategoriesTableFilterComposer
    extends Composer<_$SlimmDatabase, $ChannelCategoriesTable> {
  $$ChannelCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));
}

class $$ChannelCategoriesTableOrderingComposer
    extends Composer<_$SlimmDatabase, $ChannelCategoriesTable> {
  $$ChannelCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));
}

class $$ChannelCategoriesTableAnnotationComposer
    extends Composer<_$SlimmDatabase, $ChannelCategoriesTable> {
  $$ChannelCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$ChannelCategoriesTableTableManager extends RootTableManager<
    _$SlimmDatabase,
    $ChannelCategoriesTable,
    ChannelCategoryRow,
    $$ChannelCategoriesTableFilterComposer,
    $$ChannelCategoriesTableOrderingComposer,
    $$ChannelCategoriesTableAnnotationComposer,
    $$ChannelCategoriesTableCreateCompanionBuilder,
    $$ChannelCategoriesTableUpdateCompanionBuilder,
    (
      ChannelCategoryRow,
      BaseReferences<_$SlimmDatabase, $ChannelCategoriesTable,
          ChannelCategoryRow>
    ),
    ChannelCategoryRow,
    PrefetchHooks Function()> {
  $$ChannelCategoriesTableTableManager(
      _$SlimmDatabase db, $ChannelCategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelCategoriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> position = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChannelCategoriesCompanion(
            id: id,
            name: name,
            position: position,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<int> position = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChannelCategoriesCompanion.insert(
            id: id,
            name: name,
            position: position,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChannelCategoriesTableProcessedTableManager = ProcessedTableManager<
    _$SlimmDatabase,
    $ChannelCategoriesTable,
    ChannelCategoryRow,
    $$ChannelCategoriesTableFilterComposer,
    $$ChannelCategoriesTableOrderingComposer,
    $$ChannelCategoriesTableAnnotationComposer,
    $$ChannelCategoriesTableCreateCompanionBuilder,
    $$ChannelCategoriesTableUpdateCompanionBuilder,
    (
      ChannelCategoryRow,
      BaseReferences<_$SlimmDatabase, $ChannelCategoriesTable,
          ChannelCategoryRow>
    ),
    ChannelCategoryRow,
    PrefetchHooks Function()>;

class $SlimmDatabaseManager {
  final _$SlimmDatabase _db;
  $SlimmDatabaseManager(this._db);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db, _db.channels);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$ChannelCategoriesTableTableManager get channelCategories =>
      $$ChannelCategoriesTableTableManager(_db, _db.channelCategories);
}
