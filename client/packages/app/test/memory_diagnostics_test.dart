// SPDX-License-Identifier: Apache-2.0
/// The memory readout: byte formatting reads at a glance, and the panel
/// renders its lines without depending on a running process.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/memory_diagnostics.dart';
import 'package:slimm_design_system/design_system.dart';

void main() {
  group('formatBytes', () {
    test('scales through B / KB / MB / GB', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(400 * 1024 * 1024), '400 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('drops the decimal past 100 of a unit, keeps it below', () {
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
      expect(formatBytes((1.5 * 1024 * 1024).round()), '1.5 MB');
    });
  });

  testWidgets('renders the image-cache line against its cap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: const Scaffold(
          body: SingleChildScrollView(child: MemoryDiagnostics()),
        ),
      ),
    );
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Image cache'), findsOneWidget);
    expect(find.text('Image cache entries'), findsOneWidget);
    // The refresh control is present.
    expect(find.byIcon(AppIcons.retry), findsOneWidget);
  });
}
