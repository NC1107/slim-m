// SPDX-License-Identifier: Apache-2.0
/// Tests for the rail's Direct messages section: it now renders real DM
/// channels (stored locally under `kind == 'dm'`, see `providers/dms.dart`)
/// instead of the permanent empty state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_app/src/providers/dms.dart';
import 'package:slimm_app/src/widgets/channel_rail_sections.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

Channel _dm(String id, String name, {int cursor = 0, int lastReadSeq = 0}) =>
    Channel(
      id: id,
      name: name,
      kind: dmChannelKind,
      createdAt: 0,
      cursor: cursor,
      lastReadSeq: lastReadSeq,
    );

void main() {
  testWidgets('an empty list shows the honest empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(
          body: DirectMessagesSection(channels: [], selectedId: null),
        ),
      ),
    );

    expect(find.textContaining('No direct messages yet'), findsOneWidget);
  });

  testWidgets('a real DM channel renders as a row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: DirectMessagesSection(
            channels: [_dm('dm-1', 'Priya')],
            selectedId: null,
          ),
        ),
      ),
    );

    expect(find.text('Priya'), findsOneWidget);
    expect(find.textContaining('No direct messages yet'), findsNothing);
  });

  testWidgets('an unread DM shows the unread marker', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: DirectMessagesSection(
            channels: [_dm('dm-1', 'Priya', cursor: 5, lastReadSeq: 2)],
            selectedId: null,
          ),
        ),
      ),
    );

    expect(find.byKey(AppListRow.unreadDotKey), findsOneWidget);
  });

  testWidgets('tapping a DM opens its channel route', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: DirectMessagesSection(
              channels: [_dm('dm-1', 'Priya')],
              selectedId: null,
            ),
          ),
        ),
        GoRoute(
          path: '/channels/:channelId',
          builder: (context, state) => Scaffold(
            body: Text('channel:${state.pathParameters['channelId']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: buildTheme(Brightness.light, AppTokens.light),
        routerConfig: router,
      ),
    );

    await tester.tap(find.text('Priya'));
    await tester.pumpAndSettle();

    expect(find.text('channel:dm-1'), findsOneWidget);
  });
}
