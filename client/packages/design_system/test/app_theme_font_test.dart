// SPDX-License-Identifier: Apache-2.0
/// `ListTile` resolves its title style with `titleTextStyle ??
/// tileTheme.titleTextStyle ?? defaults.titleTextStyle`, never merging our
/// override over the family-carrying default it replaces. A family-less
/// `AppText.*` style handed to it therefore loses IBM Plex Sans silently
/// rather than failing loudly. See `_familyNamed`'s own doc comment in
/// `app_theme.dart` for the full mechanism, and why `InputDecorationTheme`
/// does not need the same treatment.
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
}
