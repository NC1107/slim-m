// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The on-disk database is encrypted, an existing plaintext one is migrated
/// without losing rows, and a lost key clears the cache instead of breaking
/// the app - see docs/decisions/0042-encrypt-local-database.md.
///
/// Every test runs in its own temp directory against a fake key store, so no
/// real keychain entry is read or written.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_data/src/connection/native.dart'
    show slimmDatabaseFileName;
import 'package:slimm_data/src/connection/encrypted_database.dart';

class _FakeKeys implements DatabaseKeyStore {
  _FakeKeys([this.key]);

  String? key;
  bool failReads = false;
  bool dropWrites = false;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (failReads) throw StateError('keychain locked');
    return key;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    if (!dropWrites) key = value;
  }
}

const _plainHeader = 'SQLite format 3\u0000';

api.ChannelCategory _category(String id) =>
    api.ChannelCategory(id: id, name: 'name-$id', position: 0, createdAt: 1);

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('laneA12-encrypted-db-');
    file = File(p.join(dir.path, slimmDatabaseFileName));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String header() =>
      String.fromCharCodes(file.readAsBytesSync().sublist(0, 16));

  Future<SlimmDatabase> open(
    _FakeKeys keys, {
    void Function(DatabaseResetReason)? onReset,
  }) async =>
      SlimmDatabase(
        await openSlimmDatabase(
          keys: keys,
          directoryPath: dir.path,
          onReset: onReset,
        ),
      );

  Future<void> seedPlaintext(List<String> ids) async {
    final db = SlimmDatabase(NativeDatabase(file));
    await MessageStore(db).replaceCategories(ids.map(_category).toList());
    await db.close();
  }

  Future<List<String>> categoryIds(SlimmDatabase db) async {
    final rows = await MessageStore(db).allCategories();
    return rows.map((r) => r.id).toList()..sort();
  }

  test('a fresh install creates an encrypted database and stores a key',
      () async {
    final keys = _FakeKeys();
    final db = await open(keys);
    await MessageStore(db).replaceCategories([_category('a')]);
    await db.close();

    expect(header(), isNot(_plainHeader));
    expect(keys.key, matches(RegExp(r'^[0-9a-f]{64}$')));
    final reopened = await open(keys);
    expect(await categoryIds(reopened), ['a']);
    await reopened.close();
  });

  test('a row written once is not readable as plaintext in the file', () async {
    final keys = _FakeKeys();
    final db = await open(keys);
    await MessageStore(db).replaceCategories([_category('needle-marker')]);
    await db.close();

    final raw = String.fromCharCodes(file.readAsBytesSync());
    expect(raw.contains('needle-marker'), isFalse);
  });

  test('migrating a plaintext database keeps every row', () async {
    await seedPlaintext(['a', 'b', 'c']);
    expect(header(), _plainHeader);
    final keys = _FakeKeys();

    final resets = <DatabaseResetReason>[];
    final db = await open(keys, onReset: resets.add);

    expect(await categoryIds(db), ['a', 'b', 'c']);
    await db.close();
    expect(resets, isEmpty);
    expect(header(), isNot(_plainHeader));
    expect(File('${file.path}.encrypting').existsSync(), isFalse);
  });

  test('migration reads rows still sitting in the write-ahead log', () async {
    final db = SlimmDatabase(NativeDatabase(file, setup: (d) {
      d.execute('PRAGMA journal_mode = WAL');
      d.execute('PRAGMA wal_autocheckpoint = 0');
    }));
    await MessageStore(db).replaceCategories([_category('in-wal')]);
    expect(File('${file.path}-wal').lengthSync(), greaterThan(0));

    final keys = _FakeKeys();
    final prepared = await prepareEncryptedDatabase(file: file, keys: keys);
    await db.close();

    expect(prepared.reset, isNull);
    final migrated = await open(keys);
    expect(await categoryIds(migrated), ['in-wal']);
    await migrated.close();
  });

  test('a crash before the rename leaves the plaintext file whole', () async {
    await seedPlaintext(['a', 'b']);
    final before = file.readAsBytesSync();
    File('${file.path}.encrypting').writeAsBytesSync([1, 2, 3, 4]);
    final keys = _FakeKeys('ab' * 32);

    final db = await open(keys);

    expect(await categoryIds(db), ['a', 'b']);
    await db.close();
    expect(header(), isNot(_plainHeader));
    expect(before.sublist(0, 16), _plainHeader.codeUnits);
  });

  test('a crash after the key was minted but before encrypting recovers',
      () async {
    await seedPlaintext(['a']);
    final keys = _FakeKeys(generateDatabaseKey());

    final db = await open(keys);

    expect(await categoryIds(db), ['a']);
    await db.close();
  });

  test('a stale plaintext sidecar after the rename does not break the open',
      () async {
    await seedPlaintext(['a']);
    final keys = _FakeKeys();
    final first = await open(keys);
    await MessageStore(first).replaceCategories([_category('a')]);
    await first.close();
    File('${file.path}-wal').writeAsBytesSync(List.filled(4152, 7));

    final db = await open(keys);

    expect(await categoryIds(db), ['a']);
    await db.close();
  });

  test('a corrupt plaintext file is cleared rather than blocking launch',
      () async {
    file.writeAsBytesSync([..._plainHeader.codeUnits, ...List.filled(4096, 9)]);
    final keys = _FakeKeys();
    final resets = <DatabaseResetReason>[];

    final db = await open(keys, onReset: resets.add);

    expect(await categoryIds(db), isEmpty);
    await db.close();
    expect(resets, [DatabaseResetReason.unreadable]);
  });

  test('a missing key clears the cache and mints a new one', () async {
    final first = _FakeKeys();
    final db = await open(first);
    await MessageStore(db).replaceCategories([_category('a')]);
    await db.close();
    final keys = _FakeKeys();
    final resets = <DatabaseResetReason>[];

    final reopened = await open(keys, onReset: resets.add);

    expect(resets, [DatabaseResetReason.keyMissing]);
    expect(await categoryIds(reopened), isEmpty);
    await reopened.close();
    expect(keys.key, isNotNull);
    expect(keys.key, isNot(first.key));
    final again = await open(keys);
    expect(await categoryIds(again), isEmpty);
    await again.close();
  });

  test('a key that no longer opens the file clears the cache', () async {
    final db = await open(_FakeKeys());
    await MessageStore(db).replaceCategories([_category('a')]);
    await db.close();
    final keys = _FakeKeys(generateDatabaseKey());
    final resets = <DatabaseResetReason>[];

    final reopened = await open(keys, onReset: resets.add);

    expect(resets, [DatabaseResetReason.unreadable]);
    await reopened.close();
  });

  test('an unreachable key store fails closed and touches nothing', () async {
    final keys = _FakeKeys();
    final db = await open(keys);
    await MessageStore(db).replaceCategories([_category('a')]);
    await db.close();
    final before = file.readAsBytesSync();
    keys.failReads = true;

    await expectLater(open(keys), throwsA(isA<LocalDatabaseKeyUnavailable>()));

    expect(file.readAsBytesSync(), before);
    expect(keys.writes, 1);
  });

  test('an unreachable key store never migrates the plaintext file', () async {
    await seedPlaintext(['a']);
    final before = file.readAsBytesSync();
    final keys = _FakeKeys()..failReads = true;

    await expectLater(open(keys), throwsA(isA<LocalDatabaseKeyUnavailable>()));

    expect(file.readAsBytesSync(), before);
    expect(keys.writes, 0);
  });

  test('a key the store did not keep is never used to encrypt', () async {
    await seedPlaintext(['a']);
    final before = file.readAsBytesSync();
    final keys = _FakeKeys()..dropWrites = true;

    await expectLater(open(keys), throwsA(isA<LocalDatabaseKeyUnavailable>()));

    expect(file.readAsBytesSync(), before);
  });

  test('generated keys are 256 bits and do not repeat', () {
    final a = generateDatabaseKey();
    final b = generateDatabaseKey();
    expect(a, hasLength(64));
    expect(a, isNot(b));
  });
}
