// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The optional TOTP second factor (decision 0048).
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file's own note.
library;

import 'models.dart';

/// What this deployment asks of a second factor.
enum TotpPolicy {
  /// New enrolments are refused. A factor somebody already switched on is
  /// still enforced, so flipping this cannot silently weaken an account, and
  /// turning one off stays possible either way.
  off,

  /// Anybody may enrol; nobody has to. The default.
  optional,

  /// Anybody may enrol, and a member holding an elevated permission is
  /// expected to.
  requiredForElevated;

  String get wire => switch (this) {
        TotpPolicy.off => 'off',
        TotpPolicy.optional => 'optional',
        TotpPolicy.requiredForElevated => 'required_for_elevated',
      };

  /// An unrecognised policy reads as [optional]. A server that grows a fourth
  /// value must not read as [off] to a client that has never heard of it,
  /// because that would hide the enrolment screen from somebody the operator
  /// is asking to enrol.
  static TotpPolicy parse(String value) => switch (value) {
        'off' => TotpPolicy.off,
        'required_for_elevated' => TotpPolicy.requiredForElevated,
        _ => TotpPolicy.optional,
      };
}

/// What a sign-in produced: a session, or a second factor still owed.
///
/// Sealed so a caller has to handle both. A nullable token pair would let the
/// challenge case be read as "signed in with no tokens", which is how a client
/// ends up navigating into an app it was never let into.
sealed class SignInOutcome {
  const SignInOutcome();
}

class SignedIn extends SignInOutcome {
  const SignedIn(this.tokens);

  final TokenPair tokens;
}

class SignInChallenged extends SignInOutcome {
  const SignInChallenged(this.challenge);

  final TotpChallenge challenge;
}

/// Whether the signed-in member has a second factor, and what the deployment
/// asks for.
class TotpStatus {
  const TotpStatus({
    required this.enabled,
    required this.pending,
    required this.recoveryCodesRemaining,
    required this.policy,
    this.confirmedAt,
  });

  /// Confirmed, and therefore demanded at sign-in.
  final bool enabled;

  /// Enrolled but never confirmed, so not demanded at sign-in. A screen seeing
  /// this offers to finish setup rather than to start over.
  final bool pending;

  final int recoveryCodesRemaining;
  final TotpPolicy policy;
  final int? confirmedAt;

  factory TotpStatus.fromJson(Map<String, dynamic> json) => TotpStatus(
        enabled: json['enabled'] as bool,
        pending: json['pending'] as bool,
        recoveryCodesRemaining: json['recovery_codes_remaining'] as int,
        policy: TotpPolicy.parse(json['policy'] as String),
        confirmedAt: json['confirmed_at'] as int?,
      );
}

/// A fresh enrolment's secret, returned once and never retrievable again.
///
/// Deliberately has no `toString`: the default would print the secret, and the
/// one thing this type must never do is reach a log.
class TotpEnrolment {
  const TotpEnrolment({required this.secret, required this.provisioningUri});

  /// Base32, for somebody typing it into an authenticator by hand.
  final String secret;

  /// The `otpauth://` URI to render as a QR code.
  final String provisioningUri;

  factory TotpEnrolment.fromJson(Map<String, dynamic> json) => TotpEnrolment(
        secret: json['secret'] as String,
        provisioningUri: json['provisioning_uri'] as String,
      );
}

/// A password that was accepted for an account whose second factor is still
/// owed. Single-use and short-lived.
///
/// No `toString`, for the reason [TotpEnrolment] has none.
class TotpChallenge {
  const TotpChallenge({required this.challenge, required this.expiresAt});

  final String challenge;
  final int expiresAt;

  factory TotpChallenge.fromJson(Map<String, dynamic> json) => TotpChallenge(
        challenge: json['totp_challenge'] as String,
        expiresAt: json['expires_at'] as int,
      );
}
