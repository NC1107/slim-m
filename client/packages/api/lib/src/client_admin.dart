// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// Self-hosted account recovery: an admin issues a one-time code, and its
/// holder spends it to set a new password. Grouped together because they are
/// the two ends of one flow, even though the schema files them under
/// separate tags (`admin` and `auth`).
extension SlimmApiAdmin on SlimmApi {
  /// Issues a one-time password reset code for [userId]. Requires
  /// ADMINISTRATOR. The plaintext code is returned only this once; the
  /// server stores only its hash.
  Future<ResetCodeIssued> issueResetCode(String userId) async {
    final json = await _send('POST', '/admin/users/$userId/reset-code');
    return ResetCodeIssued.fromJson(json as Map<String, dynamic>);
  }

  /// Spends a reset [code] to set [newPassword]. Unauthenticated, since the
  /// point is recovering an account that cannot currently sign in. Revokes
  /// every live session on the account, since the account may be compromised
  /// rather than just locked out.
  Future<void> resetPassword({
    required String code,
    required String newPassword,
  }) =>
      _send(
        'POST',
        '/auth/reset',
        authenticated: false,
        body: {'code': code, 'new_password': newPassword},
        expectNoContent: true,
      );
}
