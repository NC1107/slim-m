// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Who may create an account on this deployment.
enum JoinPolicy {
  /// A valid invite code is required. The default, and what every deployment
  /// keeps unless somebody changes it.
  invite,

  /// Anyone who can reach the server may register. A code is still accepted,
  /// so an invite granting a role keeps working.
  open;

  String get wire => name;

  /// An unrecognised policy reads as [invite]. A server that grows a third
  /// value must not read as open to a client that has never heard of it.
  static JoinPolicy parse(String value) =>
      value == 'open' ? JoinPolicy.open : JoinPolicy.invite;
}

/// Deployment-wide settings. Both calls require MANAGE_SERVER.
extension SlimmApiSpace on SlimmApi {
  Future<JoinPolicy> spaceJoinPolicy() async {
    final json = await _send('GET', '/space/settings');
    final map = json as Map<String, dynamic>;
    return JoinPolicy.parse(map['join_policy'] as String);
  }

  Future<JoinPolicy> setSpaceJoinPolicy(JoinPolicy policy) async {
    final json = await _send(
      'PATCH',
      '/space/settings',
      body: {'join_policy': policy.wire},
    );
    final map = json as Map<String, dynamic>;
    return JoinPolicy.parse(map['join_policy'] as String);
  }
}
