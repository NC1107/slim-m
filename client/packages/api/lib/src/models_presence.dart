// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

  /// An unrecognised value reads as [offline]: the same reading a caller
  /// already gets for someone who chose to appear hidden, so a server
  /// growing this enum can never make an unfamiliar status read as more
  /// present, or more distinctive, than the one state this client is already
  /// built to under-report.
  static PresenceState parse(String value) => switch (value) {
        'online' => PresenceState.online,
        'away' => PresenceState.away,
        'dnd' => PresenceState.dnd,
        _ => PresenceState.offline,
      };
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

  /// An unrecognised value reads as [hidden]. This is the caller's own
  /// choice echoed back, and defaulting toward a more public state on a
  /// value this client cannot decode risks telling someone they are visible
  /// when they are not - the one misreading this app must never produce.
  static PresenceVisibility parse(String value) => switch (value) {
        'online' => PresenceVisibility.online,
        'away' => PresenceVisibility.away,
        'dnd' => PresenceVisibility.dnd,
        _ => PresenceVisibility.hidden,
      };
}

/// One user's presence, as told to the asking caller.
class PresenceStatus {
  const PresenceStatus({required this.userId, required this.status});

  final String userId;
  final PresenceState status;

  factory PresenceStatus.fromJson(Map<String, dynamic> json) => PresenceStatus(
        userId: json['user_id'] as String,
        status: PresenceState.parse(json['status'] as String),
      );
}
