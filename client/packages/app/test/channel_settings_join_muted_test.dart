// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Channel settings screen's join-muted section: shown for a voice
/// channel only, says it is a default rather than a lock, and saves through
/// a PATCH.
library;

import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_app/src/screens/channel_settings_screen.dart';
import 'package:slimm_design_system/design_system.dart';

import 'channel_management_harness.dart';

Future<List<http.Request>> _openSettings(
  WidgetTester tester, {
  required String kind,
  required String name,
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final requests = <http.Request>[];
  await tester.pumpWidget(
    harness(
      SingleChildScrollView(
        child: ChannelSettingsPane(
          channel: channel('c1', name, kind: kind),
          wasOpen: false,
        ),
      ),
      handler: (request) {
        requests.add(request);
        return request.method == 'PATCH'
            ? http.Response(
                jsonEncode({
                  'id': 'c1',
                  'name': name,
                  'kind': kind,
                  'created_at': 0,
                  'join_muted': true,
                }),
                200,
                headers: {'content-type': 'application/json'},
              )
            : http.Response(
                request.url.path.contains('/voice')
                    ? '{"participants": []}'
                    : '{}',
                200,
              );
      },
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

void main() {
  testWidgets('a voice channel offers Join muted, explains it is a default, '
      'and saves with a PATCH', (tester) async {
    final requests = await _openSettings(tester, kind: 'voice', name: 'stage');

    expect(find.text('Join muted'), findsOneWidget);
    expect(find.textContaining('can unmute themselves'), findsOneWidget);
    expect(find.textContaining('deny Speak'), findsOneWidget);

    final toggle = find.byWidgetPredicate(
      (w) =>
          w is AppToggle &&
          w.semanticLabel == 'Members join this channel muted',
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final patched = requests.where((r) => r.url.path == '/channels/c1');
    expect(patched, hasLength(1));
    expect(jsonDecode(patched.first.body) as Map<String, dynamic>, {
      'join_muted': true,
    });
  });

  testWidgets('a text channel does not offer Join muted', (tester) async {
    await _openSettings(tester, kind: 'text', name: 'general');

    expect(find.text('Join muted'), findsNothing);
  });
}
