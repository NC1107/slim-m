// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Reaction summaries: one entry per distinct emoji on a message, from the
/// calling user's point of view.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// One emoji's tally on a message, plus whether the calling user is one of
/// the people who reacted with it.
class ReactionSummary {
  const ReactionSummary({
    required this.emoji,
    required this.count,
    required this.reacted,
  });

  /// The reaction emoji itself. User content, never chrome.
  final String emoji;

  /// How many people have reacted with this emoji.
  final int count;

  /// Whether the calling user is one of them, so a client can render the
  /// toggled state without a second request.
  ///
  /// Per-viewer, and never broadcast: the live `reactions.changed` WebSocket
  /// event carries a different, `reacted`-less shape
  /// (`ReactionTally` in events.dart) rather than this one, so the two are
  /// deliberately distinct types a caller cannot confuse.
  final bool reacted;

  factory ReactionSummary.fromJson(Map<String, dynamic> json) =>
      ReactionSummary(
        emoji: json['emoji'] as String,
        count: json['count'] as int,
        reacted: json['reacted'] as bool,
      );
}
