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

  /// Unix milliseconds.
  final int createdAt;

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        id: json['id'] as String,
        name: json['name'] as String,
        permissions: json['permissions'] as int,
        isEveryone: json['is_everyone'] as bool,
        createdAt: json['created_at'] as int,
      );
}

/// What a channel permission overwrite targets: a role held by many members,
/// or one member directly.
enum OverwriteTarget {
  role,
  member;

  String get wire => name;
}
