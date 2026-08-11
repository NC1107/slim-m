// SPDX-License-Identifier: Apache-2.0
/// A channel row's right-click/long-press menu: opening it always, and
/// managing it (the same sheet the kebab already opens) only for a caller
/// who holds MANAGE_CHANNELS - the identical gate `ManagedChannelRow`'s own
/// kebab already uses, reused rather than a second permission check.
///
/// The trailing group covers the regression `channel_rail_reorder.dart`'s
/// own doc comment names: with two or more channels a manager's row is also
/// wrapped in a drag-start listener racing this exact menu's long press for
/// the same held gesture, and the menu used to win every time, making a
/// reorder drag unreachable. A held press must now do nothing on such a
/// row; a right-click must still reach the menu regardless.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_app/src/widgets/channel_rail_sections.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

Channel _channel(String id, String name) => Channel(
  id: id,
  name: name,
  kind: 'text',
  createdAt: 0,
  position: 0,
  cursor: 0,
  lastReadSeq: 0,
  isPersonalSpace: false,
);

GoRouter _router(Channel channel, {required bool canManage}) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: ChannelCategorySections(
          channels: [channel],
          categories: const [],
          selectedId: null,
          canManage: canManage,
          onReorder: (_) {},
        ),
      ),
    ),
    GoRoute(
      path: '/channels/:channelId',
      builder: (context, state) =>
          Scaffold(body: Text('channel:${state.pathParameters['channelId']}')),
    ),
  ],
);

/// Two channels, so `ReorderableChannelRows` actually wraps each row in its
/// drag-start listener - the shape a lone channel above never exercises.
Widget _reorderableHarness({required bool canManage}) => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(
      body: ChannelCategorySections(
        channels: [_channel('c1', 'general'), _channel('c2', 'design')],
        categories: const [],
        selectedId: null,
        canManage: canManage,
        onReorder: (_) {},
      ),
    ),
  ),
);

Widget _harness(GoRouter router) => ProviderScope(
  child: MaterialApp.router(
    theme: buildTheme(Brightness.light, AppTokens.light),
    routerConfig: router,
  ),
);

Future<void> _openMenu(WidgetTester tester) => tester.tapAt(
  tester.getCenter(find.text('general')),
  buttons: kSecondaryButton,
  kind: PointerDeviceKind.mouse,
);

void main() {
  testWidgets(
    'a manager sees both Open channel and Manage channel on a right-click',
    (tester) async {
      final channel = _channel('c1', 'general');
      await tester.pumpWidget(_harness(_router(channel, canManage: true)));
      await tester.pump();

      await _openMenu(tester);
      await tester.pumpAndSettle();

      expect(find.text('Open channel'), findsOneWidget);
      expect(find.text('Manage channel...'), findsOneWidget);
    },
  );

  testWidgets(
    'a plain member sees only Open channel, the same gate the kebab uses',
    (tester) async {
      final channel = _channel('c1', 'general');
      await tester.pumpWidget(_harness(_router(channel, canManage: false)));
      await tester.pump();

      await _openMenu(tester);
      await tester.pumpAndSettle();

      expect(find.text('Open channel'), findsOneWidget);
      expect(
        find.text('Manage channel...'),
        findsNothing,
        reason:
            'MANAGE_CHANNELS is what gates the kebab; the menu must not '
            'offer a route around that',
      );
    },
  );

  testWidgets('Manage channel opens the same sheet the kebab does', (
    tester,
  ) async {
    final channel = _channel('c1', 'general');
    await tester.pumpWidget(_harness(_router(channel, canManage: true)));
    await tester.pump();

    await _openMenu(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage channel...'));
    await tester.pumpAndSettle();

    expect(find.text('Manage channel'), findsOneWidget);
    expect(find.text('Delete channel'), findsOneWidget);
  });

  testWidgets('Open channel navigates to the channel route', (tester) async {
    final channel = _channel('c1', 'general');
    await tester.pumpWidget(_harness(_router(channel, canManage: false)));
    await tester.pump();

    await _openMenu(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open channel'));
    await tester.pumpAndSettle();

    expect(find.text('channel:c1'), findsOneWidget);
  });

  testWidgets(
    'a held press on a reorderable row starts a drag rather than opening '
    'the menu',
    (tester) async {
      await tester.pumpWidget(_reorderableHarness(canManage: true));
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('general')),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);

      expect(
        find.text('Open channel'),
        findsNothing,
        reason: 'the drag listener must win the arena, not the menu',
      );

      await gesture.moveBy(const Offset(0, 200));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.text('Open channel'),
        findsNothing,
        reason: 'a completed drag must not leave the menu open either',
      );
    },
  );

  testWidgets('a right-click still reaches the menu on a reorderable row', (
    tester,
  ) async {
    await tester.pumpWidget(_reorderableHarness(canManage: true));
    await tester.pump();

    await tester.tapAt(
      tester.getCenter(find.text('general')),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Open channel'), findsOneWidget);
    expect(find.text('Manage channel...'), findsOneWidget);
  });

  testWidgets(
    'a held press still opens the menu when the row is not reorderable',
    (tester) async {
      // Not reorderable, so ReorderableChannelRows uses a plain column here.
      await tester.pumpWidget(_reorderableHarness(canManage: false));
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('general')),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Open channel'), findsOneWidget);
    },
  );
}
