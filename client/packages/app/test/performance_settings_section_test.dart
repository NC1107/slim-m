// SPDX-License-Identifier: Apache-2.0
/// The performance pane carries both memory dials - attachment preview quality
/// and the image-cache cap - each stating its current value with the default
/// marked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/performance_settings_section.dart';
import 'package:slimm_design_system/design_system.dart';

void main() {
  testWidgets('shows both dials, each with its default marked', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const Scaffold(
            body: SingleChildScrollView(child: PerformanceSettingsSection()),
          ),
        ),
      ),
    );

    expect(find.text('Auto-download media'), findsOneWidget);
    expect(find.text('Autoplay GIFs'), findsOneWidget);
    expect(find.text('Attachment preview quality'), findsOneWidget);
    expect(find.text('Image cache'), findsOneWidget);
    expect(find.text('Message page size'), findsOneWidget);
    // Each row states its current value, and every current is the default.
    expect(find.text('Always (default)'), findsOneWidget);
    expect(find.text('On (default)'), findsOneWidget);
    expect(find.text('Sharp (default)'), findsOneWidget);
    expect(find.text('100 MB (default)'), findsOneWidget);
    expect(find.text('Standard (50, default)'), findsOneWidget);
  });
}
