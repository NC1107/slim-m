// SPDX-License-Identifier: Apache-2.0
/// `SettingsEntityRow` replaced five independent hand-rolled copies of one
/// shape (roles, invites, emoji, removed members, categories). The copies had
/// already drifted in two ways worth pinning here, because both would drift
/// again the moment somebody hand-rolls a sixth.
///
/// The error banner sat *inside* the card in four of them and *above* it in
/// `invites_screen`, so a failed revoke pushed the whole list down rather than
/// annotating the row it belonged to.
///
/// And only `roles_screen` reserved empty action slots, with its own comment
/// explaining why: without it, a row offering fewer buttons slides its
/// remaining ones right and no two rows in the list line up.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/settings_entity_row.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the inline failure annotates the row, below its own content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const SettingsEntityRow(
          headline: 'weekend-invite',
          error: 'Could not revoke the invite.',
        ),
      ),
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(
      tester.getRect(find.byType(AppErrorState)).top,
      greaterThan(tester.getRect(find.text('weekend-invite')).bottom),
      reason:
          'invites_screen put this above the card, which shoved every row '
          'below it down the page instead of marking the one that failed',
    );
  });

  testWidgets('no failure means no banner and no reserved space', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const SettingsEntityRow(headline: 'weekend-invite')),
    );

    expect(find.byType(AppErrorState), findsNothing);
  });

  testWidgets('detail lines render under the headline, in the order given', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const SettingsEntityRow(
          headline: 'weekend-invite',
          details: [
            SettingsEntityDetail('3/10 uses'),
            SettingsEntityDetail('Grants moderator'),
          ],
        ),
      ),
    );

    final headline = tester.getRect(find.text('weekend-invite'));
    final first = tester.getRect(find.text('3/10 uses'));
    final second = tester.getRect(find.text('Grants moderator'));

    expect(first.top, greaterThan(headline.top));
    expect(second.top, greaterThan(first.top));
  });

  testWidgets('derived metadata elides, but text a person wrote wraps', (
    tester,
  ) async {
    const reason =
        'Posted an invite link to another, unrelated Space in '
        'three channels after being asked to stop';

    await tester.pumpWidget(
      _harness(
        const SizedBox(
          width: 300,
          child: SettingsEntityRow(
            headline: 'Grace Hopper',
            details: [
              SettingsEntityDetail('@grace'),
              SettingsEntityDetail(reason, wrap: true),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text(reason)).overflow,
      isNot(TextOverflow.ellipsis),
      reason:
          'this shipped for one capture as "Posted an invite link to another, '
          'unrelat..." - the one line the moderator opened the screen to read',
    );
    expect(
      tester.widget<Text>(find.text('@grace')).overflow,
      TextOverflow.ellipsis,
      reason:
          'a handle is short by construction and keeps the list even when '
          'clipped, so the default stays elide',
    );
  });

  testWidgets('a null action reserves its slot, so two rows offering '
      'different buttons still line up', (tester) async {
    Widget row(bool canDelete) => SettingsEntityRow(
      headline: canDelete ? 'moderator' : '@everyone',
      actions: [
        SettingsEntityActions(
          children: [
            AppIconButton(
              icon: AppIcons.edit,
              semanticLabel: 'Edit',
              onPressed: () {},
            ),
            if (canDelete)
              AppIconButton(
                icon: AppIcons.delete,
                semanticLabel: 'Delete',
                onPressed: () {},
              )
            else
              null,
          ],
        ),
      ],
    );

    await tester.pumpWidget(_harness(row(true)));
    final withDelete = tester.getRect(find.byIcon(AppIcons.edit));

    await tester.pumpWidget(_harness(row(false)));
    final withoutDelete = tester.getRect(find.byIcon(AppIcons.edit));

    expect(
      withoutDelete.left,
      withDelete.left,
      reason:
          'the edit button must land at the same x whether or not the row '
          'also offers delete - roles_screen had to hand-roll this and every '
          'other list simply did not have it',
    );
  });
}
