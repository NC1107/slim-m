// SPDX-License-Identifier: Apache-2.0
/// The fingerprint screen renders values a possibly-hostile server supplied, so
/// a malformed identity must look wrong rather than throw.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/server_fingerprint_step.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.dark, AppTokens.dark),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('a short fingerprint and an out-of-range swatch do not throw', (
    tester,
  ) async {
    // What a server that wants this screen to fail would send: too few groups
    // for the two rows, and colour indices past the six-entry palette.
    await tester.pumpWidget(
      _host(
        FingerprintDisplay(
          identity: const api.ServerIdentity(
            publicKey: 'not-really-base64',
            fingerprint: 'short',
            fingerprintGroups: ['dead', 'beef'],
            colorStrip: [99, -3, 0, 6],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('dead'), findsOneWidget);
  });

  testWidgets('an empty identity renders nothing rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FingerprintDisplay(
          identity: const api.ServerIdentity(
            publicKey: '',
            fingerprint: '',
            fingerprintGroups: [],
            colorStrip: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
