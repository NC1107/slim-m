// SPDX-License-Identifier: Apache-2.0
/// Admin-issued account recovery.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// A freshly issued one-time password reset code.
///
/// Shown only this once: the server stores only its hash, so this is the
/// caller's only chance to hand it to the account holder out of band.
class ResetCodeIssued {
  const ResetCodeIssued({required this.code, required this.expiresAt});

  final String code;

  /// Unix milliseconds at which the code stops being usable.
  final int expiresAt;

  factory ResetCodeIssued.fromJson(Map<String, dynamic> json) =>
      ResetCodeIssued(
        code: json['code'] as String,
        expiresAt: json['expires_at'] as int,
      );

  /// Deliberately hides the code, so an accidental interpolation into a log
  /// cannot leak a working credential.
  @override
  String toString() => 'ResetCodeIssued(expiresAt: $expiresAt)';
}
