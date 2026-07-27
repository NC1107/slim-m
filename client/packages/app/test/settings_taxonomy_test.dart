// SPDX-License-Identifier: Apache-2.0
/// Settings is three groups, and which group a section lands in must not
/// depend on who is looking.
///
/// The regression this pins: the About section was the last child of the
/// list with no group header of its own, so it inherited whichever header
/// rendered last. A permissioned caller read the app version under "Space",
/// an ordinary member read the same row under "Personal", because the Space
/// group is hidden entirely from a caller holding none of its bits.
library;

import 'package:flutter_test/flutter_test.dart';

import 'settings_harness.dart';

/// Every personal section's header, in the order the screen builds them.
const _personal = [
  'Avatar',
  'Appearance',
  'Presence',
  'Notifications',
  'Voice',
  'Devices',
  'Blocked',
  'Account',
];

const _spaceRows = [
  'Reports',
  'Invites',
  'Roles',
  'Channel permissions',
  'Emoji',
];

double _topOf(WidgetTester tester, String text) =>
    tester.getRect(find.text(text)).top;

void main() {
  setUpAll(mockAppVersion);

  testWidgets('an administrator sees three named groups, personal then Space '
      'then App, with every section inside the right one', (tester) async {
    useTallViewport(tester);
    await pumpSettings(tester, allPermissionBits, scrollToBottom: false);

    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);

    final personal = _topOf(tester, 'Personal');
    final space = _topOf(tester, 'Space');
    final app = _topOf(tester, 'App');
    expect(personal, lessThan(space));
    expect(space, lessThan(app));

    for (final section in _personal) {
      expect(
        _topOf(tester, section),
        inExclusiveRange(personal, space),
        reason: '$section is not inside the Personal group',
      );
    }

    for (final row in _spaceRows) {
      expect(
        _topOf(tester, row),
        inExclusiveRange(space, app),
        reason: '$row is not inside the Space group',
      );
    }

    expect(
      _topOf(tester, 'Version'),
      greaterThan(app),
      reason: 'the app version is not inside the App group',
    );
  });

  /// The other half of the same property. With the Space group hidden there
  /// is nothing between Account and the version row, which is exactly the
  /// arrangement that used to file the version under "Personal".
  testWidgets('an ordinary member sees the App group too, and the version '
      'stays out of Personal', (tester) async {
    useTallViewport(tester);
    await pumpSettings(tester, 0, scrollToBottom: false);

    expect(find.text('Space'), findsNothing);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);

    final app = _topOf(tester, 'App');
    for (final section in _personal) {
      expect(
        _topOf(tester, section),
        lessThan(app),
        reason: '$section has drifted under the App group',
      );
    }

    expect(
      _topOf(tester, 'Version'),
      greaterThan(app),
      reason: 'the app version fell back into the Personal group',
    );
  });

  /// Blocking is reversible, and that is the thing a hesitating user needs to
  /// know. The wordiness pass cut the half of this sentence that said so.
  testWidgets('the blocked section says blocking can be undone', (
    tester,
  ) async {
    useTallViewport(tester);
    await pumpSettings(tester, 0, scrollToBottom: false);

    expect(
      find.text('They are not told. Unblocking restores their messages.'),
      findsOneWidget,
    );
  });
}
