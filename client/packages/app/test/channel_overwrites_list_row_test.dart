// SPDX-License-Identifier: Apache-2.0
/// `ChannelOverwritesScreen` and the three picker sheets it opens used to be
/// bare `ListTile`s: taller, differently inset, and with none of
/// `AppListRow`'s hover, press or keyboard-focus chrome.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_design_system/design_system.dart';

import 'channel_overwrites_harness.dart';

void main() {
  testWidgets('the whole channel, role and member picking flow is AppListRow '
      'throughout, never a bare ListTile', (tester) async {
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

    // The trigger row and sheet the shared helper above already used.
    expect(find.byType(ListTile), findsNothing);

    await tester.tap(find.text('Choose a role'));
    await tester.pumpAndSettle();

    expect(
      find.byType(ListTile),
      findsNothing,
      reason: 'the role picker sheet is open here',
    );
    expect(find.text('Moderators'), findsOneWidget);

    await tester.tap(find.text('Moderators'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(AppListRow), findsWidgets);
  });
}
