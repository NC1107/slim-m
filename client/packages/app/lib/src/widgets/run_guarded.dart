// SPDX-License-Identifier: Apache-2.0
/// Running a write that can fail, and saying so if it does.
///
/// Twenty-six places wrote the same six lines: set busy, await the call,
/// invalidate a provider, catch `ApiException`, clear busy, show a
/// `SnackBar`. Two things were wrong with that beyond the repetition. The
/// message interpolated the exception, so a transport failure put
/// `POST /invites failed: SocketException...` in front of a user. And a
/// `SnackBar` is the wrong shape for a failure at all under the error
/// grammar: it floats away from the control and leaves no record.
///
/// This keeps the control flow in one place and hands the failure back as a
/// plain sentence for the caller to render where the action was - with
/// [AppErrorState] for a surface that has room, or an inline caption where
/// it does not.
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_api/api.dart' as api;

/// Runs [action], returning null on success or a human sentence on failure.
///
/// [whatFailed] names the action from the user's side ("revoke the invite"),
/// and the returned sentence reads "Could not revoke the invite." A server
/// message is appended only when it is worth reading: a `BadRequest` carries
/// the server's own explanation of what was wrong with the request, while a
/// transport failure carries a Dart exception string that helps nobody.
Future<String?> runGuarded({
  required String whatFailed,
  required Future<void> Function() action,
}) async {
  try {
    await action();
    return null;
  } on api.BadRequestException catch (e) {
    return 'Could not $whatFailed. ${e.message}';
  } on api.ConflictException catch (e) {
    return 'Could not $whatFailed. ${e.message}';
  } on api.ForbiddenException {
    return 'Could not $whatFailed: you are not allowed to do that.';
  } on api.UnauthorizedException {
    return 'Could not $whatFailed: you are signed out. Sign in and try again.';
  } on api.RateLimitedException {
    return 'Could not $whatFailed: too many requests just now. '
        'Wait a moment and try again.';
  } on api.TransportException {
    return 'Could not $whatFailed: the server could not be reached. '
        'Nothing was changed.';
  } on api.ApiException {
    return 'Could not $whatFailed.';
  }
}

/// Holds the last failure from [runGuarded] for a widget that renders it.
///
/// A mixin rather than a base class so it composes with the `ConsumerState`
/// these screens already extend.
mixin GuardedActionState<T extends StatefulWidget> on State<T> {
  String? _actionError;

  /// The last failure, or null. Render it where the action is.
  String? get actionError => _actionError;

  /// Clears it, for a dismiss control.
  void clearActionError() {
    if (_actionError != null) setState(() => _actionError = null);
  }

  /// [runGuarded], with the result stored and a `mounted` check after the
  /// await - the guard every one of the twenty-six copies had to remember.
  Future<bool> guard({
    required String whatFailed,
    required Future<void> Function() action,
  }) async {
    final failure = await runGuarded(whatFailed: whatFailed, action: action);
    if (!mounted) return failure == null;
    setState(() => _actionError = failure);
    return failure == null;
  }
}
