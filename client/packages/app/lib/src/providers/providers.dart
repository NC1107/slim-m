// SPDX-License-Identifier: Apache-2.0
/// Dependency wiring.
///
/// One Riverpod container holds everything; there is no second DI mechanism.
/// Providers are written by hand rather than generated so the graph is readable
/// in one file and there is no build step between changing a dependency and
/// running the app.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_data/data.dart';

/// Where the app points. Overridden at startup from saved settings, and by
/// tests to aim at a throwaway server.
final serverUrlProvider = StateProvider<Uri>(
  (ref) => Uri.parse('http://localhost:8080'),
);

/// The session, shared by everything that talks to the server so a refresh in
/// one place is seen everywhere.
final sessionProvider = Provider<SessionStore>((ref) {
  final store = SessionStore();
  ref.onDispose(store.dispose);
  return store;
});

/// The API client for the current server.
final apiProvider = Provider<SlimmApi>((ref) {
  final api = SlimmApi(
    baseUrl: ref.watch(serverUrlProvider),
    session: ref.watch(sessionProvider),
  );
  ref.onDispose(api.close);
  return api;
});

/// Whether there is a signed-in session, as a stream so routing can react.
final signedInProvider = StreamProvider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  return session.changes
      .map((tokens) => tokens != null)
      .distinct()
      .transform(_startWith(session.isSignedIn));
});

/// The local database. Opened once and closed with the container.
final databaseProvider = FutureProvider<SlimmDatabase>((ref) async {
  final directory = await getApplicationSupportDirectory();
  final db = SlimmDatabase(
    NativeDatabase.createInBackground(
        File(p.join(directory.path, 'slimm.sqlite'))),
  );
  ref.onDispose(db.close);
  return db;
});

/// The local store, once the database is open.
final storeProvider = FutureProvider<MessageStore>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MessageStore(db);
});

/// Persisted settings, for the saved server address and session.
final preferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

/// Prepends a current value to a stream, so a listener attaching late still
/// sees the present state rather than waiting for the next change.
StreamTransformer<T, T> _startWith<T>(T initial) {
  return StreamTransformer<T, T>.fromBind(
    (source) async* {
      yield initial;
      yield* source;
    },
  );
}
