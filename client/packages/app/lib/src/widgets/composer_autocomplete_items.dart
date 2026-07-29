// SPDX-License-Identifier: Apache-2.0
/// Turning a trigger into a ranked list of things to insert.
///
/// Pure, and separate from the overlay that draws it, for the same reason
/// [autocompleteQueryAt] is separate from both: ranking is where "did it
/// offer the obvious thing first" lives, and that is a list-in, list-out
/// question rather than a widget one.
library;

import 'package:slimm_api/api.dart' as api;

import 'composer_autocomplete_query.dart';
import 'emoji_catalog.dart';

/// Most rows to offer at once.
///
/// Short deliberately: the point of an inline autocomplete is that the right
/// answer is visible without reading, and a list long enough to scroll is a
/// picker, which this app already has behind the `+` button.
const int maxAutocompleteRows = 8;

/// One offer. [insert] is what replaces the trigger span, and it carries its
/// own trailing space where one is wanted, so the caller never has to know
/// which kinds want one.
class AutocompleteSuggestion {
  const AutocompleteSuggestion({
    required this.insert,
    required this.label,
    this.detail,
    this.glyph,
    this.imageEmoji,
    this.userId,
  });

  final String insert;

  /// What the row reads as, and what a screen reader says.
  final String label;

  /// A muted second column: an emoji's shortcode, a member's username.
  final String? detail;

  /// A literal character to draw at the leading edge, for a unicode emoji.
  final String? glyph;

  /// A deployment emoji to draw from its own image instead.
  final api.CustomEmoji? imageEmoji;

  /// A member, so the row can show their avatar rather than a generic glyph.
  final String? userId;
}

/// A slash command: text substitution only.
///
/// Deliberately a tiny set of things that need nothing from the server. There
/// is no command system in this product - no `/me` message flag, no bot
/// dispatch - so anything beyond substitution would be a promise the wire
/// protocol cannot keep. When one exists, this list is where it plugs in.
const _commands = <(String, String, String)>[
  ('shrug', r'¯\_(ツ)_/¯', 'append a shrug'),
  ('tableflip', '(╯°□°)╯︵ ┻━┻', 'flip a table'),
  ('unflip', '┬─┬ ノ( ゜-゜ノ)', 'put it back'),
];

/// The offers for [query], ranked, capped at [maxAutocompleteRows].
List<AutocompleteSuggestion> autocompleteSuggestions({
  required AutocompleteQuery query,
  required List<api.CustomEmoji> custom,
  required List<api.UserProfile> members,
  String? selfId,
}) => switch (query.kind) {
  AutocompleteKind.emoji => _emoji(query.term, custom),
  AutocompleteKind.mention => _mentions(query.term, members, selfId),
  AutocompleteKind.command => _commandRows(query.term),
};

List<AutocompleteSuggestion> _emoji(
  String term,
  List<api.CustomEmoji> custom,
) => [
  for (final result in pickerResults(
    query: term,
    category: EmojiCategory.custom,
    recent: const [],
    custom: custom,
  ).take(maxAutocompleteRows))
    switch (result) {
      DeploymentEmoji(:final emoji) => AutocompleteSuggestion(
        // A shortcode is already delimited, so it needs no extra colons.
        insert: '${emoji.shortcode} ',
        label: emoji.shortcode,
        detail: 'this Space',
        imageEmoji: emoji,
      ),
      UnicodeEmoji(:final emoji) => AutocompleteSuggestion(
        insert: '${emoji.char} ',
        label: emoji.name,
        detail: ':${emoji.shortName}:',
        glyph: emoji.char,
      ),
    },
];

/// Members whose username or display name contains [term].
///
/// Yourself excluded: mentioning yourself notifies nobody, and the row would
/// sit where the person you meant to reach was about to appear. Prefix
/// matches lead, because that is what somebody typing three letters means.
List<AutocompleteSuggestion> _mentions(
  String term,
  List<api.UserProfile> members,
  String? selfId,
) {
  final candidates = members.where((m) => m.id != selfId).where((m) {
    if (term.isEmpty) return true;
    return m.username.toLowerCase().contains(term) ||
        m.displayName.toLowerCase().contains(term);
  }).toList();

  candidates.sort((a, b) {
    final aStarts = a.username.toLowerCase().startsWith(term);
    final bStarts = b.username.toLowerCase().startsWith(term);
    if (aStarts != bStarts) return aStarts ? -1 : 1;
    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });

  return [
    for (final m in candidates.take(maxAutocompleteRows))
      AutocompleteSuggestion(
        insert: '@${m.username} ',
        label: m.displayName,
        detail: '@${m.username}',
        userId: m.id,
      ),
  ];
}

List<AutocompleteSuggestion> _commandRows(String term) => [
  for (final (name, text, detail) in _commands)
    if (term.isEmpty || name.startsWith(term))
      AutocompleteSuggestion(insert: '$text ', label: '/$name', detail: detail),
];
