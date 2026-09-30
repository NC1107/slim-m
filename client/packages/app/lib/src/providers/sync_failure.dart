// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Why the last sync attempt failed, kept apart from `SyncStatus` because the
/// recovery differs: one is worth waiting out and the other is not.
///
/// `SyncController.start` used to swallow the cause outright (`catch (_)`), so
/// an unreachable server and a server that refused the session both surfaced
/// as the same "Offline, retrying". Retrying fixes the first and can never fix
/// the second, and the reader had no way to tell which one they were in.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'sync_controller.dart';

/// The two kinds of sync failure worth telling apart on screen.
enum SyncFailure {
  /// The request never arrived, or the answer was unreadable. Self-healing:
  /// the backoff loop keeps trying and it comes back on its own.
  unreachable,

  /// The server answered and said no. Waiting changes nothing; signing in
  /// again, or being granted the permission back, is what fixes it.
  refused,
}

/// Which failure [error] is.
///
/// Anything that is not an outright refusal counts as unreachable, including a
/// local database failure: those are also transient from the reader's side,
/// and claiming the server refused something it never saw would be worse.
SyncFailure syncFailureFor(Object error) => switch (error) {
  api.UnauthorizedException() ||
  api.ForbiddenException() => SyncFailure.refused,
  _ => SyncFailure.unreachable,
};

/// Why sync is not live right now, or null while it is (or has not failed yet).
final syncFailureProvider = StateProvider<SyncFailure?>((ref) => null);

/// The accessible label for the connection, given the status actually shown
/// ([displaySyncStatus]) and the reason behind it.
///
/// A refusal drops the word "retrying": the loop does keep trying, but saying
/// so invites the reader to wait for something that will not happen.
String connectionLabel(SyncStatus status, SyncFailure? failure) =>
    switch (status) {
      SyncStatus.live => 'Connected to the server',
      SyncStatus.connecting => 'Connecting to the server',
      SyncStatus.offline =>
        failure == SyncFailure.refused
            ? 'The server refused this session'
            : 'Offline, retrying',
    };
