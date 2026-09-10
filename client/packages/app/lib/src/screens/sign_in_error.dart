// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Which part of the sign-in form a failure belongs to, and which failure maps
/// to which part.
///
/// Split out of `sign_in_screen.dart` for that file's line budget, and it is
/// the right seam: this is a pure mapping from a wire failure to a place on
/// screen, with no widget and no state in it.
library;

import 'package:slimm_api/api.dart';

import '../api_failure.dart';

/// Which field a failure lands on, per error grammar 03: an error belongs to
/// the thing that failed, with that thing's content preserved.
/// [SignInErrorField.form] is the fallback for failures no one field owns.
enum SignInErrorField { server, username, password, form }

/// Where [e] belongs and what to say about it.
///
/// Says what actually happened. "Something went wrong" tells nobody whether to
/// fix their password or wait a minute.
(SignInErrorField, String) signInErrorFor(ApiException e) => switch (e) {
  UnauthorizedException() => (
    SignInErrorField.password,
    'Wrong username or password.',
  ),
  ConflictException() => (
    SignInErrorField.username,
    'That username is already taken.',
  ),
  BadRequestException(:final message) => (
    SignInErrorField.form,
    sentenceCase(message),
  ),
  RateLimitedException() => (
    SignInErrorField.form,
    'Too many attempts just now. Wait a moment and try again.',
  ),
  UnavailableException() => (
    SignInErrorField.form,
    'The server is busy. Try again shortly.',
  ),
  TransportException() => (
    SignInErrorField.server,
    "This Space didn't answer. It may be restarting, or the address may be "
        'wrong. Nothing was sent.',
  ),
  _ => (
    SignInErrorField.form,
    'The server refused that. ${sentenceCase(e.message)}',
  ),
};
