// SPDX-License-Identifier: Apache-2.0
/// Profiles: a public [UserProfile] and the caller's own richer [Me].
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// A user's public profile, visible to anyone signed in to the same
/// deployment: the shape returned for another member, never the caller's own
/// richer view.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.createdAt,
    this.avatarUpdatedAt,
    this.roles = const [],
  });

  final String id;
  final String username;
  final String displayName;

  /// Unix milliseconds.
  final int createdAt;

  /// When this user's avatar was last set, or null for no avatar. Not itself
  /// fetchable: pass it as a client-side cache key alongside
  /// [SlimmApi.fetchAvatar], since the fetch endpoint itself ignores any
  /// query string. Absent (not just null) on a server older than the avatar
  /// feature, which a caller must treat as unknown rather than as "no
  /// avatar".
  final int? avatarUpdatedAt;

  /// Role names, for a badge beside the member. Excludes `@everyone`, which
  /// every member holds, so an empty list means "no badge" rather than "no
  /// data".
  final List<String> roles;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String,
        createdAt: json['created_at'] as int,
        avatarUpdatedAt: json['avatar_updated_at'] as int?,
        // Absent on a server older than the roles field, which is not the same
        // as a member holding none; both render no badge, so an empty list is
        // the honest reading of either.
        roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? const [],
      );
}

/// The caller's own profile plus their effective base (deployment-level)
/// permissions.
///
/// Base permissions ignore any per-channel overwrite. They are a UI nicety
/// for deciding what to show; every write is still re-authorized server-side
/// from scratch regardless of what this says.
class Me {
  const Me({
    required this.id,
    required this.username,
    required this.displayName,
    required this.createdAt,
    required this.permissions,
    this.avatarUpdatedAt,
  });

  final String id;
  final String username;
  final String displayName;

  /// Unix milliseconds.
  final int createdAt;

  /// The raw permission bitmask; see the server's `Permissions` type for what
  /// each bit means.
  final int permissions;

  /// Same meaning as [UserProfile.avatarUpdatedAt].
  final int? avatarUpdatedAt;

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String,
        createdAt: json['created_at'] as int,
        permissions: json['permissions'] as int,
        avatarUpdatedAt: json['avatar_updated_at'] as int?,
      );
}
