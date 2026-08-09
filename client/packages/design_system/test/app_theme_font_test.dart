// SPDX-License-Identifier: Apache-2.0
/// Two widgets that both build their text under a bare `DefaultTextStyle`
/// rather than a `.merge`, so a family-less `AppText.*` style handed to
/// either loses IBM Plex Sans silently rather than failing loudly.
/// `ListTile` resolves its title style with `titleTextStyle ??
/// tileTheme.titleTextStyle ?? defaults.titleTextStyle`; `SnackBar` wraps its
/// whole content in `DefaultTextStyle(style: contentTextStyle!, ...)`,
/// found while rendering `app_snackbar.dart`'s own choke point and reading
/// as blank boxes rather than the message. See `_familyNamed`'s own doc
/// comment in `app_theme.dart` for the full mechanism, and why
/// `InputDecorationTheme` does not need the same treatment.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

void main() {
  testWidgets('a bare ListTile title keeps the app typeface', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: const Scaffold(
          body: ListTile(title: Text('choose a channel')),
        ),
      ),
    );
    await tester.pump();

    // Text.style is null here regardless of the fix, so read RenderParagraph.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('choose a channel'),
    );
    expect(paragraph.text.style?.fontFamily, AppFonts.sans);
  });

  testWidgets('a SnackBar shown through the theme keeps the app typeface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('a message')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('a message'),
    );
    expect(paragraph.text.style?.fontFamily, AppFonts.sans);
  });
}
