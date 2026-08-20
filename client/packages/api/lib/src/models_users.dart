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
    this.roleIds = const [],
    this.timedOutUntil,
    this.statusText,
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

  /// The same roles as ids, positionally matching [roles].
  ///
  /// Deciding "does this member hold that role" needs these, not the names:
  /// nothing stops two roles sharing a name, and matching by name lights up
  /// both. Empty on a server older than the field, which is why the roles
  /// sheet treats an id it cannot resolve as unknown rather than as unheld.
  final List<String> roleIds;

  /// When this member's timeout lifts, in Unix milliseconds, or null if they
  /// are not timed out. Already resolved against the clock server-side, so an
  /// elapsed timeout arrives as null rather than as a past deadline.
  final int? timedOutUntil;

  /// A short free-text status line this member set for themselves, or null
  /// for none - shown in the member pane under the name. Absent (not just
  /// null) on a server older than this field, which a caller must treat as
  /// unknown rather than as "no status".
  final String? statusText;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String,
        createdAt: json['created_at'] as int,
        avatarUpdatedAt: json['avatar_updated_at'] as int?,
        // Absent on a server older than the roles field is not the same as a
        // member holding none, but both render no badge, so empty reads either.
        roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? const [],
        roleIds:
            (json['role_ids'] as List<dynamic>?)?.cast<String>() ?? const [],
        timedOutUntil: json['timed_out_until'] as int?,
        statusText: json['status_text'] as String?,
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
    this.timedOutUntil,
    this.timeoutReason,
    this.statusText,
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

  /// When the caller's own timeout lifts, or null.
  ///
  /// [permissions] already has the timeout subtracted, so a UI hiding actions
  /// on a missing bit needs no separate rule; this is what lets it say why
  /// rather than leaving somebody with a dead composer and no explanation.
  final int? timedOutUntil;

  /// Why the caller was timed out, or null if they are not timed out, or the
  /// moderator left no reason. Self-view only: the server never puts this on
  /// [UserProfile], which other members can read.
  final String? timeoutReason;

  /// The caller's own status line; same meaning as [UserProfile.statusText].
  final String? statusText;

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String,
        createdAt: json['created_at'] as int,
        permissions: json['permissions'] as int,
        avatarUpdatedAt: json['avatar_updated_at'] as int?,
        timedOutUntil: json['timed_out_until'] as int?,
        timeoutReason: json['timeout_reason'] as String?,
        statusText: json['status_text'] as String?,
      );
}
