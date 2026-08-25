// SPDX-License-Identifier: Apache-2.0
/// The role and member picker sheets `_pickTarget` opens must actually show
/// rows once their provider resolves. Both were empty regardless of load
/// state: `_pickTarget` pre-captured `ref.read(rolesProvider).valueOrNull`
/// (or `membersProvider`) as a plain closure variable, which reads
/// `AsyncLoading` on a cold `autoDispose` provider and never rebuilds once
/// the fetch actually lands.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_data/data.dart' show Channel;
import 'package:slimm_design_system/design_system.dart';

import 'channel_overwrites_harness.dart';

void main() {
  testWidgets('an initial channel is pre-selected, skipping the picker', (
    tester,
  ) async {
    await pumpToTargetPicker(
      tester,
      handler: (request) => http.Response('{}', 404),
      initialChannel: const Channel(
        id: 'c1',
        name: 'general',
        kind: 'text',
        createdAt: 0,
        position: 0,
        cursor: 0,
        lastReadSeq: 0,
        isPersonalSpace: false,
      ),
    );

    // The channel is already chosen: its name shows and the picker prompt does not.
    expect(find.text('general'), findsWidgets);
    expect(find.text('Choose a channel'), findsNothing);
  });

  testWidgets('the role picker sheet lists the roles once they load', (
    tester,
  ) async {
    await pumpToTargetPicker(
      tester,
      handler: (request) => request.url.path == '/roles'
          ? http.Response(
              jsonEncode([
                {
                  'id': 'r1',
                  'name': 'Moderators',
                  'permissions': 0,
                  'is_everyone': false,
                  'created_at': 0,
                },
              ]),
              200,
            )
          : http.Response('{}', 200),
    );

    // The Role tab is the default; open its picker.
    await tester.tap(find.text('Choose a role'));
    await tester.pumpAndSettle();

    expect(
      find.text('Moderators'),
      findsOneWidget,
      reason:
          'the sheet must render the role once rolesProvider resolves, '
          'not stay empty forever',
    );
  });

  testWidgets('the member picker sheet lists the members once they load', (
    tester,
  ) async {
    await pumpToTargetPicker(
      tester,
      handler: (request) => request.url.path == '/members'
          ? http.Response(
              jsonEncode([
                {
                  'id': 'u2',
                  'username': 'kit',
                  'display_name': 'Kit',
                  'created_at': 0,
                },
              ]),
              200,
            )
          : http.Response('{}', 200),
    );

    await tester.tap(find.text('Member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a member'));
    await tester.pumpAndSettle();

    expect(
      find.text('Kit'),
      findsOneWidget,
      reason:
          'the sheet must render the member once membersProvider '
          'resolves, not stay empty forever',
    );
  });

  testWidgets(
    'clearing an overwrite reports the resulting state, not a claimed change',
    (tester) async {
      // Tall enough that the sixteen permission rows leave "Clear" on screen.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var deleted = false;
      await pumpToTargetPicker(
        tester,
        handler: (request) {
          if (request.url.path == '/roles') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'r1',
                  'name': 'Moderators',
                  'permissions': 0,
                  'is_everyone': false,
                  'created_at': 0,
                },
              ]),
              200,
            );
          }
          if (request.method == 'DELETE' &&
              request.url.path == '/channels/c1/overwrites/role/r1') {
            deleted = true;
            return http.Response('', 204);
          }
          return http.Response('{}', 200);
        },
      );

      await tester.tap(find.text('Choose a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderators'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Clear').last);
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
      expect(
        find.textContaining('cleared'),
        findsNothing,
        reason:
            'there is no read-back route, so the screen never knew whether '
            'an overwrite existed to clear in the first place',
      );
      expect(
        find.textContaining('now inherits every permission'),
        findsOneWidget,
      );
      // Drains the toast's own dismiss timer so it is not still pending once this test tears down.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    "Allow reads this channel's own answer, not the caller's base set - "
    'denied here even though the base set (see channelOverwritesMe) grants '
    'everything',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpToTargetPicker(
        tester,
        channelPermissions: 0,
        handler: (request) => request.url.path == '/roles'
            ? http.Response(
                jsonEncode([
                  {
                    'id': 'r1',
                    'name': 'Moderators',
                    'permissions': 0,
                    'is_everyone': false,
                    'created_at': 0,
                  },
                ]),
                200,
              )
            : http.Response('{}', 200),
      );

      await tester.tap(find.text('Choose a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderators'));
      await tester.pumpAndSettle();

      final row = tester.widget<AppSegmentedControl>(
        find
            .ancestor(
              of: find.text('Allow'),
              matching: find.byType(AppSegmentedControl),
            )
            .first,
      );
      expect(
        row.options.firstWhere((o) => o.label == 'Allow').disabled,
        isTrue,
        reason:
            'the base set (channelOverwritesMe) grants everything; only '
            'this channel\'s own denial explains Allow staying off',
      );
    },
  );

  testWidgets(
    'Administrator is not offered: it bypasses channel overwrites entirely',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpToTargetPicker(
        tester,
        handler: (request) => request.url.path == '/roles'
            ? http.Response(
                jsonEncode([
                  {
                    'id': 'r1',
                    'name': 'Moderators',
                    'permissions': 0,
                    'is_everyone': false,
                    'created_at': 0,
                  },
                ]),
                200,
              )
            : http.Response('{}', 200),
      );

      await tester.tap(find.text('Choose a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderators'));
      await tester.pumpAndSettle();

      expect(
        find.text('Administrator'),
        findsNothing,
        reason:
            'the evaluator returns every permission before it ever looks at '
            'a channel overwrite, so allowing or denying this bit here can '
            'never do anything',
      );
      expect(find.text('View channels'), findsOneWidget);
    },
  );

  testWidgets('setting an overwrite asks for confirmation before replacing it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var putCount = 0;
    await pumpToTargetPicker(
      tester,
      handler: (request) {
        if (request.url.path == '/roles') {
          return http.Response(
            jsonEncode([
              {
                'id': 'r1',
                'name': 'Moderators',
                'permissions': 0,
                'is_everyone': false,
                'created_at': 0,
              },
            ]),
            200,
          );
        }
        if (request.method == 'PUT' &&
            request.url.path == '/channels/c1/overwrites/role/r1') {
          putCount++;
          return http.Response('', 204);
        }
        return http.Response('{}', 200);
      },
    );

    await tester.tap(find.text('Choose a role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moderators'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'Set overwrite'));
    await tester.pumpAndSettle();

    expect(
      putCount,
      0,
      reason: 'the request must wait on the confirmation, not fire on tap',
    );
    expect(find.text('Replace this overwrite?'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Set overwrite').last);
    await tester.pumpAndSettle();

    expect(putCount, 1);
    // Drains the toast's own dismiss timer so it is not still pending once this test tears down.
    await tester.pump(const Duration(seconds: 5));
  });

  /// This screen used to catch its own `ApiException` and show it with a
  /// `SnackBar`; see `check-error-surface.py` for the gate that now catches
  /// that shape reappearing here or anywhere else in the app package.
  testWidgets(
    'a refused overwrite shows a safe sentence inline, not a SnackBar',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpToTargetPicker(
        tester,
        handler: (request) {
          if (request.url.path == '/roles') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'r1',
                  'name': 'Moderators',
                  'permissions': 0,
                  'is_everyone': false,
                  'created_at': 0,
                },
              ]),
              200,
            );
          }
          if (request.method == 'PUT' &&
              request.url.path == '/channels/c1/overwrites/role/r1') {
            return http.Response(jsonEncode({'error': 'not authorized'}), 403);
          }
          return http.Response('{}', 200);
        },
      );

      await tester.tap(find.text('Choose a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderators'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Set overwrite'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Set overwrite').last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AppErrorState), findsOneWidget);
    },
  );
}
