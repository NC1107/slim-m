// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The performance pane carries both memory dials - attachment preview quality
/// and the image-cache cap - each stating its current value with the default
/// marked. The desktop startup-splash row is covered on its
/// own in `desktop_splash_settings_row_test.dart`, the same "a new preference
/// gets its own file" shape `voice_settings_push_to_talk_test.dart` already
/// uses; this file only asserts they are present at all.
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
    // Desktop-only (isDesktopHost gate); one row now - Disabled replaced the toggle.
    expect(find.text('Startup splash'), findsOneWidget);
  });
}
