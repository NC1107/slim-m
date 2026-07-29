// SPDX-License-Identifier: Apache-2.0
/// Ranking, which is the half that decides whether Enter takes the row you
/// meant. The detector's own cases are in
/// `composer_autocomplete_query_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/composer_autocomplete_items.dart';
import 'package:slimm_app/src/widgets/composer_autocomplete_query.dart';

api.UserProfile _member(String id, String username, [String? display]) =>
    api.UserProfile(
      id: id,
      username: username,
      displayName: display ?? username,
      createdAt: 0,
    );

const _members = [
  _Fixed('u-priya', 'priya'),
  _Fixed('u-kess', 'kess'),
  _Fixed('u-dorian', 'dorian'),
  _Fixed('u-apriya', 'apriya'),
];

/// A tiny record so the fixture list can be `const`.
class _Fixed {
  const _Fixed(this.id, this.username);
  final String id;
  final String username;
}

List<api.UserProfile> get members => [
  for (final m in _members) _member(m.id, m.username),
];

AutocompleteQuery _q(AutocompleteKind kind, String term) =>
    AutocompleteQuery(kind: kind, term: term, start: 0, end: term.length + 1);

List<AutocompleteSuggestion> _for(
  AutocompleteKind kind,
  String term, {
  String? selfId,
  List<api.CustomEmoji> custom = const [],
}) => autocompleteSuggestions(
  query: _q(kind, term),
  custom: custom,
  members: members,
  selfId: selfId,
);

void main() {
  group('mentions', () {
    test('a prefix match leads a mere substring match', () {
      final rows = _for(AutocompleteKind.mention, 'priya');
      expect(rows.first.detail, '@priya');
      expect(
        rows.map((r) => r.detail),
        containsAll(['@priya', '@apriya']),
        reason: 'apriya still matches, it just does not lead',
      );
    });

    test('yourself is never offered', () {
      final rows = _for(AutocompleteKind.mention, '', selfId: 'u-kess');
      expect(
        rows.map((r) => r.detail),
        isNot(contains('@kess')),
        reason: 'mentioning yourself notifies nobody and takes a row',
      );
    });

    test('an empty term offers everyone, so @ alone is useful', () {
      expect(_for(AutocompleteKind.mention, '').length, members.length);
    });

    test(
      'inserts the username with a trailing space, not the display name',
      () {
        final row = _for(AutocompleteKind.mention, 'dor').first;
        expect(row.insert, '@dorian ');
      },
    );

    test('matches display name as well as username', () {
      final rows = autocompleteSuggestions(
        query: _q(AutocompleteKind.mention, 'nick'),
        custom: const [],
        members: [_member('u-1', 'npc', 'nick')],
      );
      expect(rows, hasLength(1));
    });

    test('carries the id, so the row can show a real avatar', () {
      expect(_for(AutocompleteKind.mention, 'dor').first.userId, 'u-dorian');
    });
  });

  group('emoji', () {
    test('a real shortcode search returns something insertable', () {
      final rows = _for(AutocompleteKind.emoji, 'smile');
      expect(rows, isNotEmpty);
      expect(rows.first.insert, isNotEmpty);
      expect(
        rows.first.insert.endsWith(' '),
        isTrue,
        reason:
            'the trailing space is part of the insert, so no caller has to '
            'know which kinds want one',
      );
    });

    test('is capped, so the list never becomes a scrolling picker', () {
      // A term matching a great many entries.
      expect(
        _for(AutocompleteKind.emoji, 'e').length,
        lessThanOrEqualTo(maxAutocompleteRows),
      );
    });
  });

  group('commands', () {
    test('a bare slash offers the whole set', () {
      final rows = _for(AutocompleteKind.command, '');
      expect(rows.map((r) => r.label), contains('/shrug'));
      expect(rows.length, greaterThan(1));
    });

    test('filters by prefix', () {
      final rows = _for(AutocompleteKind.command, 'shr');
      expect(rows, hasLength(1));
      expect(rows.first.label, '/shrug');
    });

    test('inserts the text, not the command name', () {
      final row = _for(AutocompleteKind.command, 'shrug').first;
      expect(row.insert, isNot(contains('shrug')));
      expect(row.insert.trim(), isNotEmpty);
    });

    test('an unknown command offers nothing rather than everything', () {
      expect(_for(AutocompleteKind.command, 'nope'), isEmpty);
    });
  });
}
