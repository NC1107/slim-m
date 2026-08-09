// SPDX-License-Identifier: Apache-2.0
/// A message row's avatar and name were not clickable at all: no way to
/// reach the author's profile or start a DM from the place a reader actually
/// encounters them. Both now open the same [showMemberProfile] popover the
/// member pane already opens, via [AuthorProfileTapTarget].
///
/// The semantics half is the point of this file, not an afterthought:
/// CLAUDE.md's "54, the resize bar" entry records a real bug where a
/// `GestureDetector`'s own tap action bled a control's label onto an
/// unrelated ancestor, found only by dumping the real semantics tree - so
/// this dumps the real tree too, rather than trusting that
/// `excludeFromSemantics` did what it was meant to.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/user_profiles.dart';
import 'package:slimm_app/src/widgets/author_profile_tap_target.dart';
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_app/src/widgets/user_avatar.dart';

import 'message_row_harness.dart';

const _author = api.UserProfile(
  id: 'author-1',
  username: 'priya',
  displayName: 'Priya',
  createdAt: 0,
);

Widget _row({String? authorId = 'author-1', bool grouped = false}) =>
    MessageRow(
      message: message(authorId: authorId),
      grouped: grouped,
      showNewDivider: false,
      knownUsernames: const {},
      onRetry: noop,
      onDiscard: noop,
      onPickReaction: (_) {},
      onReactionTap: (_) {},
      onVote: (_) {},
      actions: noActions,
      editing: false,
      onSubmitEdit: (_) {},
      onCancelEdit: noop,
    );

List<Override> _resolvedProfile() => [
  userProfileProvider('author-1').overrideWith((ref) async => _author),
];

/// The [AuthorProfileTapTarget] keyboard focus currently sits inside, by its
/// own semantic label - null when focus is elsewhere entirely.
String? _focusedTapTargetLabel() => FocusManager
    .instance
    .primaryFocus
    ?.context
    ?.findAncestorWidgetOfExactType<AuthorProfileTapTarget>()
    ?.semanticLabel;

/// Tabs forward until focus lands inside the [AuthorProfileTapTarget] whose
/// label matches [label], so neither test depends on how many other focusable
/// things (the row's own context-menu stop, say) happen to sit ahead of it.
Future<bool> _tabTo(WidgetTester tester, String label) async {
  for (var step = 0; step < 8; step++) {
    if (_focusedTapTargetLabel() == label) return true;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  return _focusedTapTargetLabel() == label;
}

Future<bool> _tabToAvatar(WidgetTester tester) =>
    _tabTo(tester, 'View profile');

Future<bool> _tabToName(WidgetTester tester) =>
    _tabTo(tester, 'Priya, view profile');

void main() {
  testWidgets('tapping the avatar opens the author\'s profile popover', (
    tester,
  ) async {
    await tester.pumpWidget(harness(_row(), overrides: _resolvedProfile()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AuthorAvatar));
    await tester.pumpAndSettle();

    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('tapping the name opens the same popover', (tester) async {
    await tester.pumpWidget(harness(_row(), overrides: _resolvedProfile()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Priya').first);
    await tester.pumpAndSettle();

    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets(
    'a grouped continuation row offers no tap target at all: it has no '
    'avatar or name to begin with',
    (tester) async {
      await tester.pumpWidget(
        harness(_row(grouped: true), overrides: _resolvedProfile()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AuthorAvatar), findsNothing);
      expect(find.byType(AuthorProfileTapTarget), findsNothing);
    },
  );

  testWidgets(
    'an anonymised author (no id at all) offers no tap target, rather than '
    'one that would fail once pressed',
    (tester) async {
      await tester.pumpWidget(
        harness(_row(authorId: null), overrides: _resolvedProfile()),
      );
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('View profile'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'before the profile resolves, the row offers no tap target either - a '
    'profile that cannot yet load must not be offered as though it can',
    (tester) async {
      await tester.pumpWidget(harness(_row()));
      await tester.pump();

      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('View profile'), findsNothing);
      semantics.dispose();
    },
  );

  group('keyboard', () {
    setUp(() {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    });
    tearDown(() {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });

    testWidgets('Tab reaches the avatar and Enter opens the popover', (
      tester,
    ) async {
      await tester.pumpWidget(harness(_row(), overrides: _resolvedProfile()));
      await tester.pumpAndSettle();

      expect(await _tabToAvatar(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        find.text('Message'),
        findsOneWidget,
        reason: 'the avatar was reachable but never runnable',
      );
    });

    testWidgets('the name is reachable too, and Space also opens it', (
      tester,
    ) async {
      await tester.pumpWidget(harness(_row(), overrides: _resolvedProfile()));
      await tester.pumpAndSettle();

      expect(await _tabToName(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(find.text('Message'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets(
      'the avatar and name each carry their own button label and a real tap '
      'action, and neither label bleeds onto the other or onto an unrelated '
      'sibling - checked against the real dumped tree, not assumed',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(
          harness(
            Column(children: [_row(), const Text('Unrelated sibling text')]),
            overrides: _resolvedProfile(),
          ),
        );
        await tester.pumpAndSettle();

        final owner = tester
            .binding
            // ignore: deprecated_member_use
            .pipelineOwner;
        final dump = owner.semanticsOwner!.rootSemanticsNode!.toStringDeep();

        final avatarNode = tester.getSemantics(
          find.byType(AuthorProfileTapTarget).at(0),
        );
        final nameNode = tester.getSemantics(
          find.byType(AuthorProfileTapTarget).at(1),
        );

        expect(
          avatarNode.label,
          'View profile',
          reason:
              'a merge with AppAvatar\'s own "Priya" label would still '
              'contain this substring, which is why this checks the whole '
              'label rather than merely that it appears',
        );
        expect(nameNode.label, 'Priya, view profile');
        expect(
          avatarNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          nameNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          dump,
          contains('Unrelated sibling text'),
          reason:
              'the sibling keeps its own untouched label rather than losing '
              'it to a merge, the exact shape "54, the resize bar" found',
        );

        semantics.dispose();
      },
    );
  });
}
