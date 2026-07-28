// SPDX-License-Identifier: Apache-2.0
/// Personal and Space settings are separate screens now, so the regression
/// this used to pin (the version row inheriting whichever group happened to
/// render last, because Space could be hidden on the shared screen) cannot
/// recur structurally: the App group lives only on the personal screen, which
/// always renders regardless of permission. What is still worth pinning is
/// that the App group's position on that screen does not move depending on
/// who is looking, and that neither screen leaks the other's content.
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
  'Who can join',
  'Emoji',
];

double _topOf(WidgetTester tester, String text) =>
    tester.getRect(find.text(text)).top;

/// Shared body for the two permission scenarios below: one [testWidgets]
/// call per scenario, each with its own pump and its own teardown, rather
/// than pumping twice inside one test (a second [ProviderContainer] pumped
/// before the first is disposed left `PushController`'s foreground heartbeat
/// timer pending at test end).
Future<void> _expectAppGroupAfterPersonal(
  WidgetTester tester,
  int permissions,
) async {
  useTallViewport(tester);
  await pumpPersonalSettings(tester, permissions, scrollToBottom: false);

  expect(find.text('App'), findsOneWidget);
  final app = _topOf(tester, 'App');
  for (final section in _personal) {
    expect(
      _topOf(tester, section),
      lessThan(app),
      reason:
          '$section has drifted under the App group '
          '(permissions: $permissions)',
    );
  }
  expect(
    _topOf(tester, 'Version'),
    greaterThan(app),
    reason:
        'the app version is not inside the App group '
        '(permissions: $permissions)',
  );
}

void main() {
  setUpAll(mockAppVersion);

  testWidgets(
    'the App group sits after every personal section for an ordinary '
    'member',
    (tester) => _expectAppGroupAfterPersonal(tester, 0),
  );

  testWidgets(
    'the App group sits after every personal section for a caller who can '
    'also reach Space settings',
    (tester) => _expectAppGroupAfterPersonal(tester, allPermissionBits),
  );

  testWidgets('personal settings never shows Space content', (tester) async {
    await pumpPersonalSettings(tester, allPermissionBits);

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

    for (final section in _personal) {
      expect(
        find.text(section),
        findsNothing,
        reason: '$section leaked onto Space settings',
      );
    }
    expect(find.text('App'), findsNothing);
    expect(find.text('Version'), findsNothing);
  });

  /// Blocking is reversible, and that is the thing a hesitating user needs to
  /// know. The wordiness pass cut the half of this sentence that said so.
  testWidgets('the blocked section says blocking can be undone', (
    tester,
  ) async {
    useTallViewport(tester);
    await pumpPersonalSettings(tester, 0, scrollToBottom: false);

    expect(
      find.text('They are not told. Unblocking restores their messages.'),
      findsOneWidget,
    );
  });
}
