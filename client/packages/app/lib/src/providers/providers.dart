// SPDX-License-Identifier: Apache-2.0
/// Dependency wiring.
///
/// One Riverpod container holds everything; there is no second DI mechanism.
/// Providers are written by hand rather than generated so the graph is readable
/// in one file and there is no build step between changing a dependency and
/// running the app.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_platform/platform.dart';

/// Where the app points. Overridden at startup from saved settings, and by
/// tests to aim at a throwaway server.
final serverUrlProvider = StateProvider<Uri>(
  (ref) => Uri.parse('http://localhost:8080'),
);

/// An invite code chosen during onboarding, redeemed once an account exists.
final pendingInviteProvider = StateProvider<String?>((ref) => null);

/// The handle the persisted session is stored under, in [keyStoreProvider].
const sessionTokenHandle = 'session_token_pair';

/// The handle the server address that session belongs to is stored under.
/// Written and read alongside [sessionTokenHandle], never independently:
/// a session is only meaningful together with the server that issued it, and
/// [serverUrlProvider]'s own default (localhost) is useless against a real
/// deployment.
const serverUrlHandle = 'server_url';

/// The handle for the flag that says this install has launched before. Lives
/// in [preferencesProvider], not [keyStoreProvider]: the point of it is that
/// it does NOT survive an iOS/Android reinstall the way the platform
/// keychain does, so its absence is how [restoreSession] tells a genuinely
/// fresh install apart from an ordinary relaunch.
const hasLaunchedBeforeKey = 'slimm.has_launched_before';

/// The session, shared by everything that talks to the server so a refresh in
/// one place is seen everywhere.
///
/// Every change is written straight to the key store: a login or a refresh
/// persists the new pair (with the server it belongs to), and a sign-out or a
/// rejected refresh deletes it. [restoreSession] does the other half, reading
/// it back on the next launch.
///
/// Writes are chained, not fired in parallel: a burst of rapid session
/// changes (a restore immediately followed by a refresh) must land on disk in
/// the order they happened, or a slow write can finish after a faster later
/// one and leave a stale value as the persisted state.
final sessionProvider = Provider<SessionStore>((ref) {
  final store = SessionStore();
  final keyStore = ref.read(keyStoreProvider);
  var pending = Future<void>.value();
  final subscription = store.changes.listen((tokens) {
    final serverUrl = tokens == null ? null : ref.read(serverUrlProvider);
    pending = pending
        .then((_) => _persistSession(keyStore, tokens, serverUrl))
        .catchError((Object _, StackTrace __) {
      // The server rotates refresh tokens with reuse detection: a write that
      // failed here may have left a stale, already-spent token on disk, and
      // replaying that on the next launch reads as reuse and revokes the
      // whole family. Dropping the stored session outright degrades to a
      // fresh sign-in instead of that false replay.
      if (tokens != null) {
        return keyStore.delete(sessionTokenHandle).catchError((_) {});
      }
    });
  });
  ref.onDispose(subscription.cancel);
  ref.onDispose(store.dispose);
  return store;
});

Future<void> _persistSession(
  KeyStore keyStore,
  TokenPair? tokens,
  Uri? serverUrl,
) async {
  if (tokens == null) {
    await keyStore.delete(sessionTokenHandle);
    return;
  }
  await keyStore.put(sessionTokenHandle, jsonEncode(tokens.toJson()));
  if (serverUrl != null) {
    await keyStore.put(serverUrlHandle, serverUrl.toString());
  }
}

/// Restores a persisted session from local storage before the router makes
/// its first signed-in/signed-out decision, so a relaunch does not flash
/// sign-in and then jump to channels, and restores the server address that
/// session belongs to in the same step, so a restored session is never left
/// pointed at [serverUrlProvider]'s useless default.
///
/// This only reads local storage, never the network: an access token that
/// turns out to be stale is caught by the same 401-refresh path every other
/// authenticated call already goes through, once the app is on screen and
/// sync or push registration make their first request. Blocking startup on a
/// round trip here would mean a dead connection leaves the user staring at
/// nothing rather than a working, if offline, app.
///
/// Everything here, including the very first read, runs inside the guarded
/// region: main() awaits this before runApp, so any failure of the storage
/// layer itself must degrade to "no stored session" and let the app reach the
/// sign-in screen, never crash launch outright.
Future<void> restoreSession(ProviderContainer container) async {
  final keyStore = container.read(keyStoreProvider);
  try {
    // The iOS/Android keychain outlives app deletion; this flag does not, so
    // its absence means this is the first launch since an install (fresh, or
    // a reinstall over one that was supposedly wiped). Whatever is already in
    // the keychain at that point belongs to the account signed in before,
    // not to this install, and must not come back as if nothing happened.
    final prefs = await container.read(preferencesProvider.future);
    if (prefs.getBool(hasLaunchedBeforeKey) != true) {
      await keyStore.clear();
      await prefs.setBool(hasLaunchedBeforeKey, true);
      return;
    }

    final stored = await keyStore.read(sessionTokenHandle);
    if (stored == null) return;

    final tokens =
        TokenPair.fromJson(jsonDecode(stored) as Map<String, dynamic>);

    final storedServerUrl = await keyStore.read(serverUrlHandle);
    final serverUrl =
        storedServerUrl == null ? null : Uri.tryParse(storedServerUrl);
    if (serverUrl == null || !serverUrl.hasScheme || serverUrl.host.isEmpty) {
      // A session with no usable server address restores to a connection
      // that can never work; that is the exact failure this exists to
      // prevent, so treat it the same as a corrupt session rather than
      // silently falling back to the localhost default.
      throw const FormatException('missing or invalid persisted server url');
    }
    container.read(serverUrlProvider.notifier).state = serverUrl;

    container.read(sessionProvider).set(tokens);
  } catch (_) {
    // A broken store, corrupt JSON, a missing server address, or anything
    // else here must degrade to "no stored session", never crash launch.
    await keyStore.delete(sessionTokenHandle).catchError((_) {});
  }
}

/// The caller's own profile. Real endpoint; kept here rather than beside one
/// particular widget because more than one of them (the rail footer, the
/// member pane's "message a member" affordance) need to know their own id.
final meProvider = FutureProvider.autoDispose<Me>(
  (ref) => ref.watch(apiProvider).me(),
);

/// The API client for the current server.
final apiProvider = Provider<SlimmApi>((ref) {
  final api = SlimmApi(
    baseUrl: ref.watch(serverUrlProvider),
    session: ref.watch(sessionProvider),
  );
  ref.onDispose(api.close);
  return api;
});

/// Builds a throwaway unauthenticated client for a server that is not (yet)
/// the current one: probing a candidate address during onboarding or
/// sign-in. A provider rather than a bare constructor call so tests can
/// substitute a fake transport; the caller owns close().
final probeApiProvider = Provider<SlimmApi Function(Uri)>(
  (ref) => (baseUrl) => SlimmApi(baseUrl: baseUrl),
);

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
  final db = SlimmDatabase(await openSlimmDatabase());
  ref.onDispose(db.close);
  return db;
});

/// The local store, once the database is open.
final storeProvider = FutureProvider<MessageStore>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MessageStore(db);
});

/// Ordinary app settings, kept separate from [keyStoreProvider]: nothing
/// stored here is a secret. Today this backs exactly one thing,
/// [hasLaunchedBeforeKey], and it backs it precisely because this file does
/// NOT survive an iOS/Android reinstall the way the platform keychain does.
final preferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

/// Where device secrets live: the session token pair and the push private key
/// today, later signing and agreement keys for E2EE. The platform keychain on
/// iOS and Android, an owner-only-permissioned file on desktop; see
/// `createPersistentKeyStore` for why desktop does not also use the keychain
/// backend.
final keyStoreProvider =
    Provider<KeyStore>((ref) => createPersistentKeyStore());

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
