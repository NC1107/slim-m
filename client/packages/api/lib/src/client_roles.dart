// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
  /// subset of the caller's own effective permissions. [mentionable]
  /// defaults false, matching every other role's `@[Role Name]` waking
  /// nobody until someone opts it in.
  Future<Role> createRole({
    required String name,
    required int permissions,
    bool? mentionable,
  }) async {
    final json = await _send(
      'POST',
      '/roles',
      body: {
        'name': name,
        'permissions': permissions,
        if (mentionable != null) 'mentionable': mentionable,
      },
    );
    return Role.fromJson(json as Map<String, dynamic>);
  }

  /// Renames a role, changes its permissions, and/or its `mentionable`
  /// flag. Requires MANAGE_ROLES. Every field is optional; a field left null
  /// is unchanged. Refused if a permissions change would leave the
  /// deployment with no administrator.
  Future<Role> updateRole({
    required String roleId,
    String? name,
    int? permissions,
    bool? mentionable,
  }) async {
    final json = await _send(
      'PATCH',
      '/roles/$roleId',
      body: {
        if (name != null) 'name': name,
        if (permissions != null) 'permissions': permissions,
        if (mentionable != null) 'mentionable': mentionable,
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

  /// Every permission overwrite currently set on a channel: the read
  /// [setChannelOverwrite] never had, so an editor can see what it would
  /// replace instead of silently re-granting a deliberate denial. Requires
  /// MANAGE_ROLES in this channel specifically, the same gate
  /// [setChannelOverwrite] uses, and refuses a channel the caller cannot
  /// manage identically to one that does not exist.
  Future<List<ChannelOverwrite>> getChannelOverwrites(
    String channelId,
  ) async {
    final json = await _send('GET', '/channels/$channelId/overwrites');
    return ((json as Map<String, dynamic>)['overwrites'] as List<dynamic>)
        .map((o) => ChannelOverwrite.fromJson(o as Map<String, dynamic>))
        .toList(growable: false);
  }
}
