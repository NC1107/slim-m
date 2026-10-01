// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A manifest with no artifact for this platform must reach the person as a
/// persistent banner with the manual download on it, never as silence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_controller.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_failure.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_failure_banner.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(WidgetTester tester, SelfUpdateFailure? failure) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [selfUpdateFailureProvider.overrideWith((ref) => failure)],
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: SelfUpdateFailureBanner()),
      ),
    ),
  );
}

void main() {
  testWidgets('a platform with no artifact offers the release page', (
    tester,
  ) async {
    await _pump(
      tester,
      const SelfUpdateFailure(
        SelfUpdateFailureKind.noArtifactForPlatform,
        'Version 9.9.9 has no download for this platform yet.',
        releaseUrl: 'https://example.invalid/release',
      ),
    );
    expect(find.textContaining('no download for this platform'), findsOne);
    expect(find.text('Open release page'), findsOne);
  });

  testWidgets('a failure with no release page offers no download button', (
    tester,
  ) async {
    await _pump(
      tester,
      const SelfUpdateFailure(
        SelfUpdateFailureKind.badSignature,
        'The update could not be verified.',
      ),
    );
    expect(find.text('Open release page'), findsNothing);
    expect(find.textContaining('could not be verified'), findsOne);
  });
}
