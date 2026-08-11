// SPDX-License-Identifier: Apache-2.0
/// The exact wording `http/error.rs`'s `ApiError::Internal` and
/// `http/auth.rs`'s `validate_password` send, read from the shared fixture
/// both sides check against (`crates/slimm-server/tests/fixtures/
/// onboarding_error_strings.json`), the same technique
/// `mention_charset_cases.json` already uses for the mention regex - a
/// server-side edit to either string that forgets the fixture fails a Rust
/// test, and a fixture edit that forgets the client fails here, instead of
/// a snapshot quietly drifting from what the server actually sends.
library;

import 'dart:convert';
import 'dart:io';

/// The internal-error and password-length strings a real 500/400 from the
/// server actually carries.
class OnboardingErrorStrings {
  const OnboardingErrorStrings._(this.internalError, this.passwordLengthError);

  final String internalError;
  final String passwordLengthError;

  static OnboardingErrorStrings load() {
    final repoRoot = _findRepoRoot(Directory.current);
    final fixture = File(
      '${repoRoot.path}/crates/slimm-server/tests/fixtures/onboarding_error_strings.json',
    );
    final raw = jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
    return OnboardingErrorStrings._(
      raw['internal_error'] as String,
      raw['password_length_error'] as String,
    );
  }
}

/// Walks upward from [start] looking for schema/openapi.yaml, the same
/// repo-root anchor `message_inline_mention_charset_test.dart` already uses,
/// so this test does not depend on which directory it was invoked from.
Directory _findRepoRoot(Directory start) {
  var dir = start.absolute;
  for (var i = 0; i < 10; i++) {
    if (File('${dir.path}/schema/openapi.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'could not find schema/openapi.yaml walking up from ${start.path}; is '
    'this test running from somewhere inside the slim-m repo?',
  );
}
