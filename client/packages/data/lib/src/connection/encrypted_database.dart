// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Getting the on-disk database into a state where it opens with the key:
/// created encrypted, migrated from plaintext, or reset when the key is gone.
///
/// Every path either leaves the live file exactly as it was or replaces it
/// atomically, and none of them opens a plaintext file for the app to use.
/// See docs/decisions/0042-encrypt-local-database.md for the reasoning.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'database_key.dart';

const _plainHeader = 'SQLite format 3\u0000';
const _sqliteNotADatabase = 26;
const _sqliteCorrupt = 11;

/// The file the plaintext copy is encrypted into before it replaces the live
/// one. A leftover from a crashed run is disposable and deleted on the next.
String _stagingPath(File live) => '${live.path}.encrypting';

/// Applies [key] to a freshly opened connection. Raw-key form skips the
/// password KDF, which is pointless for a 256-bit random key and would cost
/// every open. The SQLCipher profile keeps the file readable by stock tools.
void applyDatabaseKey(Database db, String key) {
  _selectCipher(db);
  db.execute('''PRAGMA key = "x'$key'"''');
}

void _selectCipher(Database db) {
  db.execute("PRAGMA cipher = 'sqlcipher'");
  db.execute('PRAGMA legacy = 4');
}

/// A database file that opens with [key], and why the cache was cleared on the
/// way there ([reset] is null when nothing was).
typedef PreparedDatabase = ({String key, DatabaseResetReason? reset});

/// Makes [file] safe to open with the stored key.
///
/// Throws [LocalDatabaseKeyUnavailable] when the key store cannot be reached;
/// the file is not touched in that case.
Future<PreparedDatabase> prepareEncryptedDatabase({
  required File file,
  required DatabaseKeyStore keys,
}) async {
  _removeStaging(file);
  final stored = await _readKey(keys);
  switch (_stateOf(file)) {
    case _FileState.missing:
      _removeSidecars(file);
      return (key: stored ?? await _mintKey(keys), reset: null);
    case _FileState.plaintext:
      final key = stored ?? await _mintKey(keys);
      return (key: key, reset: _migratePlaintext(file, key));
    case _FileState.opaque:
      if (stored == null) {
        _deleteDatabase(file);
        const reset = DatabaseResetReason.keyMissing;
        return (key: await _mintKey(keys), reset: reset);
      }
      if (_opensWith(file, stored)) return (key: stored, reset: null);
      _deleteDatabase(file);
      return (key: stored, reset: DatabaseResetReason.unreadable);
  }
}

Future<String?> _readKey(DatabaseKeyStore keys) async {
  try {
    return await keys.read();
  } catch (error) {
    throw LocalDatabaseKeyUnavailable(error);
  }
}

/// Stores a new key and reads it back before anything is encrypted with it: a
/// database sealed with a key the store did not really keep is a database the
/// next launch has to throw away.
Future<String> _mintKey(DatabaseKeyStore keys) async {
  final key = generateDatabaseKey();
  try {
    await keys.write(key);
    if (await keys.read() != key) {
      throw StateError('the key store did not return the key it was given');
    }
  } catch (error) {
    throw LocalDatabaseKeyUnavailable(error);
  }
  return key;
}

enum _FileState { missing, plaintext, opaque }

_FileState _stateOf(File file) {
  if (!file.existsSync() || file.lengthSync() == 0) return _FileState.missing;
  final raf = file.openSync();
  try {
    final head = String.fromCharCodes(raf.readSync(_plainHeader.length));
    return head == _plainHeader ? _FileState.plaintext : _FileState.opaque;
  } finally {
    raf.closeSync();
  }
}

/// Encrypts a copy of the plaintext file, proves the copy reads back, then
/// renames it over the original.
///
/// Until that rename the plaintext file is untouched, so a crash at any earlier
/// point leaves the user's data exactly where it was and the next launch starts
/// again. The rename is the only step that changes what is on disk.
DatabaseResetReason? _migratePlaintext(File file, String key) {
  final staging = File(_stagingPath(file));
  try {
    _copyEncrypted(file, staging, key);
  } on SqliteException catch (error) {
    _removeStaging(file);
    if (!_isUnreadable(error)) rethrow;
    _deleteDatabase(file);
    return DatabaseResetReason.unreadable;
  } catch (_) {
    _removeStaging(file);
    rethrow;
  }
  _removeSidecars(file);
  staging.renameSync(file.path);
  return null;
}

void _copyEncrypted(File source, File staging, String key) {
  final rowCount = _snapshotInto(source, staging);
  final copy = sqlite3.open(staging.path);
  try {
    _selectCipher(copy);
    // Encrypts the copy in place; it is disposable, so nothing is at risk.
    copy.execute('''PRAGMA rekey = "x'$key'"''');
  } finally {
    copy.close();
  }
  final check = sqlite3.open(staging.path);
  try {
    applyDatabaseKey(check, key);
    final seen = check.select('SELECT count(*) AS n FROM sqlite_master');
    if (seen.first['n'] != rowCount) {
      throw StateError('the encrypted copy does not match the original');
    }
  } finally {
    check.close();
  }
}

/// A consistent single-file snapshot of [source], WAL content included, and
/// the number of schema objects in it.
int _snapshotInto(File source, File target) {
  final db = sqlite3.open(source.path);
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    db.execute("VACUUM INTO '${target.path.replaceAll("'", "''")}'");
    return db.select('SELECT count(*) AS n FROM sqlite_master').first['n']
        as int;
  } finally {
    db.close();
  }
}

bool _opensWith(File file, String key) {
  Database? db;
  try {
    db = sqlite3.open(file.path);
    applyDatabaseKey(db, key);
    db.select('SELECT count(*) FROM sqlite_master');
    return true;
  } on SqliteException catch (error) {
    if (_isUnreadable(error)) return false;
    rethrow;
  } finally {
    db?.close();
  }
}

bool _isUnreadable(SqliteException error) =>
    error.resultCode == _sqliteNotADatabase ||
    error.resultCode == _sqliteCorrupt;

void _deleteDatabase(File file) {
  _removeSidecars(file);
  if (file.existsSync()) file.deleteSync();
}

void _removeSidecars(File file) {
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final sidecar = File('${file.path}$suffix');
    if (sidecar.existsSync()) sidecar.deleteSync();
  }
}

void _removeStaging(File live) {
  final staging = File(_stagingPath(live));
  _removeSidecars(staging);
  if (staging.existsSync()) staging.deleteSync();
}
