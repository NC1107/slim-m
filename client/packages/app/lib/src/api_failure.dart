// SPDX-License-Identifier: Apache-2.0
/// Turning a failed request into a sentence, in the one place both
/// `runGuarded` and a bespoke catch clause can share it.
///
/// `TransportException.message` carries a method, a path and a Dart
/// exception (`client_transport.dart`'s own doc says so), which is a log
/// line, not copy: nothing here may put one of those in front of a user.
library;

import 'package:slimm_api/api.dart' as api;

/// Turns [e] into a plain sentence for [whatFailed] ("join the call"),
/// never the raw transport string a [api.TransportException] carries.
///
/// A [api.BadRequestException] or [api.ConflictException] appends the
/// server's own reason, which is worth reading; every other case names only
/// what is safe to say without it.
String describeApiFailure(String whatFailed, api.ApiException e) => switch (e) {
  api.BadRequestException() => 'Could not $whatFailed. ${e.message}',
  api.ConflictException() => 'Could not $whatFailed. ${e.message}',
  api.ForbiddenException() =>
    'Could not $whatFailed: you are not allowed to do that.',
  api.UnauthorizedException() =>
    'Could not $whatFailed: you are signed out. Sign in and try again.',
  api.RateLimitedException() =>
    'Could not $whatFailed: too many requests just now. '
        'Wait a moment and try again.',
  api.TransportException() =>
    'Could not $whatFailed: the server could not be reached. '
        'Nothing was changed.',
  api.ApiException() => 'Could not $whatFailed.',
};
