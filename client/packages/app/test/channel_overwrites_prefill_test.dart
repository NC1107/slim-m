// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `GET /channels/{channelId}/overwrites` is the read this editor never had:
/// this suite covers the two places it now lands - the "Current overwrites"
/// list itself, and the pre-fill it feeds both that list's own row tap and
/// the ordinary role/member pickers.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_app/src/screens/admin/permission_overwrite_row.dart';
import 'package:slimm_design_system/design_system.dart';

import 'channel_overwrites_harness.dart';

const _roleJson = {
  'id': 'r1',
  'name': 'Moderators',
  'permissions': 0,
  'is_everyone': false,
  'created_at': 0,
};

/// Perm.viewChannel, kept as a literal so this test does not import the
/// app's permissions module just to name one bit.
const _viewChannelBit = 1 << 1;

http.Response Function(http.Request) _handlerWithRole() =>
    (request) => request.url.path == '/roles'
    ? http.Response(jsonEncode([_roleJson]), 200)
    : http.Response('{}', 200);

AppSegmentedControl _segmentedControlFor(WidgetTester tester, String label) =>
    tester.widget<AppSegmentedControl>(
      find.byWidgetPredicate(
        (w) => w is AppSegmentedControl && w.semanticLabel == label,
      ),
    );

void main() {
  testWidgets(
    'the current overwrites section lists what is already set, resolved to '
    'a name',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpToTargetPicker(
        tester,
        handler: _handlerWithRole(),
        overwrites: [
          {'kind': 'role', 'id': 'r1', 'allow': _viewChannelBit, 'deny': 0},
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Current overwrites'), findsOneWidget);
      expect(find.text('Moderators'), findsOneWidget);
      expect(find.text('1 allowed'), findsOneWidget);
    },
  );

  testWidgets(
    'a channel with nothing set shows the empty state, not an error',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpToTargetPicker(tester, handler: _handlerWithRole());
      await tester.pumpAndSettle();

      expect(
        find.text('No overwrites set on this channel yet.'),
        findsOneWidget,
      );
      expect(find.byType(AppErrorState), findsNothing);
    },
  );

  testWidgets('tapping an existing overwrite in the current overwrites section '
      'pre-fills its allow/deny instead of opening at Inherit', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpToTargetPicker(
      tester,
      handler: _handlerWithRole(),
      overwrites: [
        {'kind': 'role', 'id': 'r1', 'allow': 0, 'deny': _viewChannelBit},
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Moderators'));
    await tester.pumpAndSettle();

    expect(
      _segmentedControlFor(tester, 'View channels').selectedIndex,
      OverwriteState.deny.index,
      reason:
          'the fetched overwrite denies this bit, so the row must '
          'open on Deny rather than Inherit',
    );
  });

  testWidgets(
    'picking the same target through the ordinary role picker pre-fills '
    'the same way as the current-overwrites row does',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpToTargetPicker(
        tester,
        handler: _handlerWithRole(),
        overwrites: [
          {'kind': 'role', 'id': 'r1', 'allow': _viewChannelBit, 'deny': 0},
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moderators').last);
      await tester.pumpAndSettle();

      expect(
        _segmentedControlFor(tester, 'View channels').selectedIndex,
        OverwriteState.allow.index,
        reason:
            'the fetched overwrite allows this bit, so picking the '
            'target through the picker sheet must pre-fill Allow too',
      );
    },
  );

  testWidgets('a target with no existing overwrite still opens on Inherit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpToTargetPicker(tester, handler: _handlerWithRole());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moderators'));
    await tester.pumpAndSettle();

    expect(
      _segmentedControlFor(tester, 'View channels').selectedIndex,
      OverwriteState.inherit.index,
    );
  });
}
