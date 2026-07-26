// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Role management and channel permission overwrites: the `roles` tag.
///
/// Every mutation here is checked twice server-side: MANAGE_ROLES gates the
/// call at all, and a second check refuses to hand out (or leave assigned) a
/// permission bit the caller does not themselves hold, so a denial here is
/// not something a retry or a different overwrite can talk past.
extension SlimmApiRoles on SlimmApi {
  /// Lists every role. Requires MANAGE_ROLES.
  Future<List<Role>> listRoles() async {
    final json = await _send('GET', '/roles');
    return (json as List<dynamic>)
        .map((r) => Role.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Creates a role. Requires MANAGE_ROLES. [permissions] must already be a
  /// subset of the caller's own effective permissions.
  Future<Role> createRole(
      {required String name, required int permissions}) async {
    final json = await _send(
      'POST',
      '/roles',
      body: {'name': name, 'permissions': permissions},
    );
    return Role.fromJson(json as Map<String, dynamic>);
  }

  /// Renames a role or changes its permissions. Requires MANAGE_ROLES. Both
  /// fields are optional; a field left null is unchanged. Refused if a
  /// permissions change would leave the deployment with no administrator.
  Future<Role> updateRole({
    required String roleId,
    String? name,
    int? permissions,
  }) async {
    final json = await _send(
      'PATCH',
      '/roles/$roleId',
      body: {
        if (name != null) 'name': name,
        if (permissions != null) 'permissions': permissions,
      },
    );
    return Role.fromJson(json as Map<String, dynamic>);
  }

  /// Deletes a role. Requires MANAGE_ROLES. Refuses to delete `@everyone`
  /// (exactly one always exists) and refuses if this role is the
  /// deployment's only remaining source of ADMINISTRATOR.
  Future<void> deleteRole(String roleId) =>
      _send('DELETE', '/roles/$roleId', expectNoContent: true);

  /// Grants a role to a member. Requires MANAGE_ROLES. Idempotent. Refused if
  /// the role carries a permission the caller does not themselves hold.
  Future<void> assignRole({required String userId, required String roleId}) =>
      _send('PUT', '/members/$userId/roles/$roleId', expectNoContent: true);

  /// Revokes a role from a member. Requires MANAGE_ROLES. Idempotent.
  /// Refused if it would leave the deployment with no administrator.
  Future<void> unassignRole({required String userId, required String roleId}) =>
      _send('DELETE', '/members/$userId/roles/$roleId', expectNoContent: true);

  /// Sets (or replaces) a channel permission overwrite for a role or member.
  /// Requires MANAGE_ROLES in this channel specifically. [allow] must be a
  /// subset of the caller's own effective permissions in this channel;
  /// [deny] is a restriction and carries no such check.
  Future<void> setChannelOverwrite({
    required String channelId,
    required OverwriteTarget kind,
    required String id,
    int allow = 0,
    int deny = 0,
  }) =>
      _send(
        'PUT',
        '/channels/$channelId/overwrites/${kind.wire}/$id',
        body: {'allow': allow, 'deny': deny},
        expectNoContent: true,
      );

  /// Clears a channel permission overwrite. Requires MANAGE_ROLES in this
  /// channel. Idempotent: clearing one that was never set still succeeds.
  Future<void> deleteChannelOverwrite({
    required String channelId,
    required OverwriteTarget kind,
    required String id,
  }) =>
      _send(
        'DELETE',
        '/channels/$channelId/overwrites/${kind.wire}/$id',
        expectNoContent: true,
      );
}
