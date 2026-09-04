// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Roles and channel permission overwrites.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// A role: a name plus a permission bitmask, assignable to members and
/// checked the same way whether it came from `@everyone` or a created role.
class Role {
  const Role({
    required this.id,
    required this.name,
    required this.permissions,
    required this.isEveryone,
    this.mentionable = false,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// The raw permission bitmask; see the server's `Permissions` type for what
  /// each bit means.
  final int permissions;

  /// Whether this is the deployment's single `@everyone` base role. Exactly
  /// one role always carries this.
  final bool isEveryone;

  /// Whether any member may wake this role's members with `@[Role Name]`
  /// with no permission of their own. Defaults false; a member holding
  /// `Perm.mentionEveryone` can still wake it regardless.
  final bool mentionable;

  /// Unix milliseconds.
  final int createdAt;

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        id: json['id'] as String,
        name: json['name'] as String,
        permissions: json['permissions'] as int,
        isEveryone: json['is_everyone'] as bool,
        mentionable: json['mentionable'] as bool? ?? false,
        createdAt: json['created_at'] as int,
      );
}

/// What a channel permission overwrite targets: a role held by many members,
/// or one member directly.
enum OverwriteTarget {
  role,
  member;

  String get wire => name;

  /// An unrecognised kind reads as [member]: a channel that could not
  /// resolve to a role stays put on the narrower, single-account reading
  /// rather than one this client would apply to a whole group of members.
  static OverwriteTarget parse(String value) =>
      value == 'role' ? OverwriteTarget.role : OverwriteTarget.member;
}

/// One permission overwrite already set on a channel: the current allow/deny
/// pair for one role or member, as `GET /channels/{channelId}/overwrites`
/// returns it. This is the read [SlimmApiRoles.setChannelOverwrite] never
/// had - without it, a routine edit could only replace an overwrite sight
/// unseen, silently re-granting a deliberate denial.
class ChannelOverwrite {
  const ChannelOverwrite({
    required this.kind,
    required this.id,
    required this.allow,
    required this.deny,
  });

  final OverwriteTarget kind;

  /// The role's or member's UUID, matching [kind].
  final String id;

  /// The permission bits this overwrite forces on.
  final int allow;

  /// The permission bits this overwrite forces off.
  final int deny;

  factory ChannelOverwrite.fromJson(Map<String, dynamic> json) =>
      ChannelOverwrite(
        kind: OverwriteTarget.parse(json['kind'] as String),
        id: json['id'] as String,
        allow: json['allow'] as int,
        deny: json['deny'] as int,
      );
}
