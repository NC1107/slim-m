// SPDX-License-Identifier: Apache-2.0
/// Personal settings is a nav beside a pane now, not nine sections in one
/// scroll, so what is worth pinning has changed with it.
///
/// The old version checked the *order* of section headers down a single
/// column, which was the right thing to check while a column was all there
/// was. What matters here instead is the taxonomy: that every category is
/// reachable, that a pane shows only its own content, and that neither
/// settings screen leaks the other's.
///
/// That last one is not cosmetic. Personal settings renders for every signed
/// in caller regardless of permission, and Space settings is hidden entirely
/// for a caller holding none of its gating bits; anything from the second
/// appearing on the first would be a permission leak rather than a layout slip.
library;

import 'package:flutter_test/flutter_test.dart';

import 'settings_harness.dart';

/// Every nav entry the personal screen offers, and the group it sits under.
const _panes = [
  ('You', 'Account & presence'),
  ('You', 'Appearance'),
  ('You', 'Notifications'),
  ('Calls', 'Voice & screen share'),
  ('Safety', 'Devices'),
  ('Safety', 'Blocked'),
  ('About', 'About slim-m'),
];

const _spaceRows = [
  'Reports',
  'Invites',
  'Roles',
  'Channel permissions',
  'Who can join',
  'Emoji',
];

void main() {
  setUpAll(mockAppVersion);

  testWidgets('every category is reachable, under its own group heading', (
    tester,
  ) async {
    useTallViewport(tester);
    await pumpPersonalSettings(tester, 0, scrollToBottom: false);

    for (final (group, pane) in _panes) {
      expect(find.text(group.toUpperCase()), findsWidgets, reason: group);
      expect(find.text(pane), findsOneWidget, reason: pane);
    }
  });

  testWidgets('the nav is the same whoever is looking', (tester) async {
    useTallViewport(tester);
    await pumpPersonalSettings(
      tester,
      allPermissionBits,
      scrollToBottom: false,
    );

    // Nothing here is permission-gated, so an admin sees the same list.
    for (final (_, pane) in _panes) {
      expect(find.text(pane), findsOneWidget, reason: pane);
    }
  });

  testWidgets('signing out is on the frame, not inside a category', (
    tester,
  ) async {
    useTallViewport(tester);
    await pumpPersonalSettings(tester, 0, scrollToBottom: false);

    // Present without opening anything, and deletion is not beside it.
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);
  });

  testWidgets('personal settings never shows Space content', (tester) async {
    useTallViewport(tester);
    await pumpPersonalSettings(
      tester,
      allPermissionBits,
      scrollToBottom: false,
    );

    for (final row in _spaceRows) {
      expect(
        find.text(row),
        findsNothing,
        reason: '$row leaked onto personal settings',
      );
    }
  });

  testWidgets('Space settings never shows personal content', (tester) async {
    await pumpSpaceSettings(tester, allPermissionBits);

    for (final (_, pane) in _panes) {
      expect(find.text(pane), findsNothing, reason: '$pane leaked onto Space');
    }
    expect(find.text('Version'), findsNothing);
  });
}
