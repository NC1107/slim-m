// SPDX-License-Identifier: Apache-2.0
/// Presence: what a caller may be told about another user, and the caller's
/// own visibility preference.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// What a caller may be told about another user's live presence. Never
/// `hidden`: a user who chose that reads as [offline] to everyone but
/// themselves, and their true state when they ask about their own id.
enum PresenceState {
  online,
  away,
  dnd,
  offline;
}

/// The caller's own visibility preference. [hidden] is the appear-offline
/// choice: the caller's own client still sees their true state; everyone
/// else sees [PresenceState.offline].
enum PresenceVisibility {
  online,
  away,
  dnd,
  hidden;

  String get wire => name;
}

/// One user's presence, as told to the asking caller.
class PresenceStatus {
  const PresenceStatus({required this.userId, required this.status});

  final String userId;
  final PresenceState status;

  factory PresenceStatus.fromJson(Map<String, dynamic> json) => PresenceStatus(
        userId: json['user_id'] as String,
        status: PresenceState.values.byName(json['status'] as String),
      );
}
