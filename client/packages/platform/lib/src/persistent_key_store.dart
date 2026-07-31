// SPDX-License-Identifier: Apache-2.0
/// Persistent [KeyStore] backends.
///
/// iOS and Android get the platform keychain (Keychain / Keystore) through
/// flutter_secure_storage, which is the right place for secrets on a phone:
/// the OS guarantees a backend is always present. Desktop deliberately does
/// not use it, even though flutter_secure_storage also ships a Linux
/// backend: that backend talks to a Secret Service over D-Bus (gnome-keyring,
/// kwallet plus ksecretsservice), and plenty of real sessions - a fresh
/// install, a window manager with no keyring agent, a container - do not run
/// one, so calls would fail unpredictably at runtime even on a machine where
/// the build itself succeeds.
///
/// Transport-only security is the project's v1 scope (see
/// docs/decisions/0001-owner-decisions.md); this file is the desktop
/// key-storage tradeoff that follows from that, not itself a recorded
/// decision: a session token and a push key are not payment credentials, so a
/// file only this OS account can open is a proportionate, always-available
/// choice for desktop rather than one that depends on a keyring agent nobody
/// promised would be running. It is weaker than a real keychain - no
/// OS-enforced encryption at rest, and it does not resist another process
/// already running as this same OS account - but it is not readable by a
/// different account on a shared machine, which is the threat this desktop
/// build actually faces today.
///
/// The web build does use flutter_secure_storage, because its browser backend
/// is the only storage a browser has: values are AES-GCM encrypted under a key
/// that itself lives in `localStorage`, so this is obfuscation against a
/// casual look, not secrecy against script running on the same origin. It is
/// also refused outright outside a secure context, so a plain-http LAN server
/// gets no persisted session at all. The web build exists to drive this UI
/// automatically; it is not a distribution target, and nothing here should be
/// read as a claim that a browser stores secrets as well as a phone does.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'host_platform.dart';
import 'key_store.dart';

/// The platform keychain, through flutter_secure_storage. Use on iOS and
/// Android, where the OS itself guarantees a secure backend.
///
/// The iOS accessibility is device-bound: excluded from iCloud sync and from
/// local device backups, and it never migrates to a new device. The default
/// (kSecAttrAccessibleWhenUnlocked) rides into both, which hands a 30-day
/// refresh token and the push private key to whatever restores that backup.
class SecureKeyStore implements KeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                // Device-bound; the default would ride into iCloud and local
                // backups. See the class doc comment.
                accessibility: KeychainAccessibility.unlocked_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Exposed only so a test can assert on the configured options without a
  /// real keychain backend behind it; nothing outside a test should need
  /// this.
  @visibleForTesting
  FlutterSecureStorage get debugStorage => _storage;

  @override
  Future<KeyHandle> put(String name, String secret) async {
    await _storage.write(key: name, value: secret);
    return name;
  }

  @override
  Future<String?> read(KeyHandle handle) => _storage.read(key: handle);

  @override
  Future<void> delete(KeyHandle handle) => _storage.delete(key: handle);

  @override
  Future<void> clear() => _storage.deleteAll();

  @override
  Future<List<int>> sign(KeyHandle handle, List<int> payload) {
    throw UnsupportedError(
      'signing needs a real key backend; wire one before shipping E2EE',
    );
  }
}

/// The desktop fallback: a single JSON file under the user's
/// application-support directory, restricted to this OS account (`chmod
/// 600`) after every write. See the library doc for why this, not
/// flutter_secure_storage, is used off mobile, and for what this does and
/// does not defend against.
///
/// Every operation is queued behind the last: two calls racing a
/// read-modify-write of the same file on disk is exactly how a concurrent
/// write (a session write landing alongside an unrelated push-key write, say)
/// would silently lose one of them.
class FileKeyStore implements KeyStore {
  FileKeyStore({Directory? directory}) : _directory = directory;

  /// Overridden by tests; production always resolves the real
  /// application-support directory.
  final Directory? _directory;

  Future<File>? _file;
  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// A rejected open must not be cached: an error is never the right thing
  /// to remember here, or one transient failure (a directory the OS could
  /// not create just then, a locked file) would disable storage for the
  /// rest of the process with no way back. The same reasoning is why
  /// http/ws/permission_cache.rs never caches a read error server-side.
  Future<File> _secretsFile() {
    return (_file ??= _open()).catchError((Object error, StackTrace stack) {
      _file = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<File> _open() async {
    final dir = _directory ?? await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'slimm_secrets.json'));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await _restrict(file);
    return file;
  }

  /// Best-effort: a missing `chmod` binary (there is no other platform this
  /// class ships to) must not break storage itself, only the extra
  /// confidentiality this call exists to add.
  Future<void> _restrict(File file) async {
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {
      // Nothing to degrade to; the file is still written, just not proven
      // private. See the class doc for the threat this narrows.
    }
  }

  Future<Map<String, dynamic>> _readAll() async {
    final file = await _secretsFile();
    final contents = await file.readAsString();
    if (contents.trim().isEmpty) return {};
    return jsonDecode(contents) as Map<String, dynamic>;
  }

  Future<void> _writeAll(Map<String, dynamic> data) async {
    final file = await _secretsFile();
    await file.writeAsString(jsonEncode(data));
    // Reasserted on every write, not just at creation, in case the file was
    // ever recreated (a fresh `create()` gets the process's default mode).
    await _restrict(file);
  }

  @override
  Future<KeyHandle> put(String name, String secret) {
    return _serialized(() async {
      final data = await _readAll();
      data[name] = secret;
      await _writeAll(data);
      return name;
    });
  }

  @override
  Future<String?> read(KeyHandle handle) {
    return _serialized(() async {
      final data = await _readAll();
      return data[handle] as String?;
    });
  }

  @override
  Future<void> delete(KeyHandle handle) {
    return _serialized(() async {
      final data = await _readAll();
      data.remove(handle);
      await _writeAll(data);
    });
  }

  @override
  Future<void> clear() => _serialized(() => _writeAll({}));

  @override
  Future<List<int>> sign(KeyHandle handle, List<int> payload) {
    throw UnsupportedError(
      'signing needs a real key backend; wire one before shipping E2EE',
    );
  }
}

/// Picks the right backend for this platform: the OS keychain on iOS and
/// Android, browser storage on the web (see the library doc for how much
/// weaker that is), and an owner-only-permissioned file everywhere else,
/// which today means the Linux desktop build.
KeyStore createPersistentKeyStore() {
  // Web is grouped with mobile rather than desktop because a browser has no
  // filesystem to write an owner-only file to.
  if (kIsWeb || isIOSHost || isAndroidHost) return SecureKeyStore();
  return FileKeyStore();
}
