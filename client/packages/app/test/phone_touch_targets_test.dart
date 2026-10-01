// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Law 2 of docs/design/desktop-vs-mobile.md: at phone width every control a
/// finger presses has a 44x44 hit area. Each case hit-tests the area around
/// the control rather than reading the size of its icon or text.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/user_profiles.dart';
import 'package:slimm_app/src/routing/close_screen.dart';
import 'package:slimm_app/src/screens/sign_in_alternatives.dart';
import 'package:slimm_app/src/widgets/author_profile_tap_target.dart';
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_app/src/widgets/profile_fields_section.dart';
import 'package:slimm_app/src/widgets/reply_quote.dart';
import 'package:slimm_app/src/widgets/settings_select_row.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row_harness.dart';
import 'touch_hit_support.dart';

const _author = api.UserProfile(
  id: 'author-1',
  username: 'priya',
  displayName: 'Priya',
  createdAt: 0,
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
}) async {
  _phone(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MessageRow _row({Message? replyTo}) => MessageRow(
  message: replyTo == null
      ? message()
      : Message(
          id: 'm2',
          channelId: 'c1',
          authorId: 'author-1',
          authorDisplayName: 'Priya',
          seq: 6,
          content: 'a reply',
          createdAt: 1700000000000,
          replyToId: replyTo.id,
          pending: false,
          failed: false,
        ),
  grouped: false,
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
  replyTo: replyTo,
  onReplyTap: noop,
);

List<Override> get _resolved => [
  userProfileProvider('author-1').overrideWith((ref) async => _author),
];

void main() {
  testWidgets('the back button in an app bar', (tester) async {
    await _pump(
      tester,
      Scaffold(
        appBar: AppBar(
          leading: const BackToButton(tooltip: 'Back', fallback: '/'),
        ),
      ),
    );
    expectTouchTarget(tester, find.byType(AppIconButton));
  });

  testWidgets('the avatar and the author name open a profile', (tester) async {
    await _pump(tester, Scaffold(body: _row()), overrides: _resolved);
    final targets = find.byType(AuthorProfileTapTarget);
    expect(targets, findsNWidgets(2));
    expectTouchTarget(
      tester,
      targets.first,
      alignment: Alignment.topLeft,
      reason: 'avatar',
    );
  });

  testWidgets('a finger does not press the 22pt author name', (tester) async {
    await _pump(tester, Scaffold(body: _row()), overrides: _resolved);
    await tester.tap(find.text('Priya').first);
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsNothing);
  });

  testWidgets('the reply quote jumps to its parent', (tester) async {
    await _pump(
      tester,
      Scaffold(
        body: _row(replyTo: message(content: 'the parent')),
      ),
      overrides: _resolved,
    );
    expectTouchTarget(
      tester,
      find.descendant(
        of: find.byType(ReplyQuote),
        matching: find.byType(InkWell),
      ),
    );
  });

  testWidgets('every profile colour swatch', (tester) async {
    await _pump(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: ProfileFieldsSection()),
      ),
      overrides: [meProvider.overrideWith((ref) => Completer<api.Me>().future)],
    );
    final swatches = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_ColorSwatch',
    );
    expect(swatches, findsNWidgets(AppCanvasColors.cursors.length));
    for (var i = 0; i < AppCanvasColors.cursors.length; i++) {
      expectTouchTarget(tester, swatches.at(i), reason: 'swatch $i');
    }
  });

  for (final creating in const [false, true]) {
    testWidgets('sign-in alternatives, creating an account: $creating', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(
          body: SignInAlternatives(
            creatingAccount: creating,
            busy: false,
            onToggleCreating: () {},
            onUseDifferentSpace: () {},
          ),
        ),
      );
      final buttons = find.byType(AppButton);
      expect(buttons, findsNWidgets(2));
      expectTouchTarget(tester, buttons.first);
      expectTouchTarget(tester, buttons.last);
    });
  }

  testWidgets('a settings select row such as the microphone picker', (
    tester,
  ) async {
    await _pump(
      tester,
      Scaffold(
        body: SettingsSelectRow<String>(
          label: 'Microphone',
          value: 'a',
          choices: const [SettingsChoice(value: 'a', label: 'System default')],
          onChanged: (_) {},
        ),
      ),
    );
    expectTouchTarget(tester, find.byType(AppListRow));
  });
}
