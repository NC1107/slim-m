// SPDX-License-Identifier: Apache-2.0
/// `SettingsSectionCard`: the fix for the owner's "settings UI is very flat"
/// report (#39). A section's rows must sit inside a bordered `AppCard`, not
/// loose on the pane background, and the header above it must keep reading
/// as a real header rather than the card's own small uppercase title.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/settings_section_header.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('wraps its rows in a bordered AppCard', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SettingsSectionCard(
          title: 'Devices',
          children: [Text('a phone')],
        ),
      ),
    );

    expect(
      find.descendant(of: find.byType(AppCard), matching: find.text('a phone')),
      findsOneWidget,
      reason: 'the row must be inside the card, not a sibling of it',
    );
  });

  testWidgets('the header stays outside the card, at its own type scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const SettingsSectionCard(
          title: 'Devices',
          children: [Text('a phone')],
        ),
      ),
    );

    expect(
      find.descendant(of: find.byType(AppCard), matching: find.text('Devices')),
      findsNothing,
      reason:
          'the section name is a SettingsSectionHeader above the card, not '
          'AppCard\'s own small uppercase title slot',
    );
    expect(find.byType(SettingsSectionHeader), findsOneWidget);
  });

  testWidgets('a description renders above the card, between it and the '
      'title', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SettingsSectionCard(
          title: 'Blocked',
          description: 'They are not told.',
          children: [Text('nobody blocked')],
        ),
      ),
    );

    expect(find.text('They are not told.'), findsOneWidget);
  });

  testWidgets('adds no horizontal inset of its own, so the screen frame is '
      'the only thing that sets one', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SettingsSectionCard(
          title: 'Devices',
          children: [Text('a phone')],
        ),
      ),
    );

    final body = tester.getRect(find.byType(Scaffold));
    final card = tester.getRect(find.byType(AppCard));

    expect(
      card.left,
      body.left,
      reason:
          'decision 0013: a section owns no horizontal padding. This used to '
          'add AppSpacing.s16 on top of the frame\'s own, which is why '
          'personal and Space settings sat at 32 while every admin screen sat '
          'at 16 - three insets across screens one tap apart.',
    );
    expect(card.right, body.right);
  });

  testWidgets('the header lines up with the card it names', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SettingsSectionCard(
          title: 'Devices',
          children: [Text('a phone')],
        ),
      ),
    );

    expect(
      tester.getRect(find.text('Devices')).left,
      tester.getRect(find.byType(AppCard)).left,
      reason:
          'a header indented differently from its own card reads as belonging '
          'to something else',
    );
  });

  testWidgets('a header action sits on the title line, outside the card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SettingsSectionCard(
          title: 'Roles',
          action: IconButton(icon: const Icon(AppIcons.add), onPressed: () {}),
          children: const [Text('a role')],
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(AppCard),
        matching: find.byType(IconButton),
      ),
      findsNothing,
      reason:
          'a section-level action acts on the whole group, so it must not '
          'read as one of the rows inside it',
    );
    expect(
      tester.getRect(find.byType(IconButton)).center.dy,
      closeTo(tester.getRect(find.text('Roles')).center.dy, 1),
    );
  });
}
