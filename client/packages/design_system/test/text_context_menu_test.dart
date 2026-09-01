// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Live Text is dropped from every field, not only the composer's.
///
/// Backlog #129 asked for the "Scan Text" entry gone, and it was - from
/// `composer_context_menu.dart` alone. Every other field went on offering it:
/// the gif search, a channel name, a category name, the sign-in fields, since
/// each is an `AppInput` and `AppInput` had no `contextMenuBuilder` at all.
///
/// The filters live here now so a field can reach them without depending on
/// the app, and the composer imports these rather than keeping its own copy -
/// it still builds its own menu, because it has a second job no other field
/// has (forcing Paste for an image-only clipboard), but the half they share
/// is one implementation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

void main() {
  test('the adaptive toolbar loses Live Text and keeps the rest', () {
    final filtered = contextMenuButtonItemsWithoutScanText([
      ContextMenuButtonItem(onPressed: () {}, type: ContextMenuButtonType.cut),
      ContextMenuButtonItem(onPressed: () {}, type: ContextMenuButtonType.copy),
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.liveTextInput,
      ),
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.paste,
      ),
    ]);

    expect(
      filtered.map((i) => i.type),
      [
        ContextMenuButtonType.cut,
        ContextMenuButtonType.copy,
        ContextMenuButtonType.paste,
      ],
      reason: 'only Live Text goes; cut, copy and paste are the menu',
    );
  });

  test('the iOS system menu loses Live Text and keeps the rest', () {
    final filtered = systemContextMenuItemsWithoutScanText(const [
      IOSSystemContextMenuItemCopy(),
      IOSSystemContextMenuItemLiveText(),
      IOSSystemContextMenuItemPaste(),
    ]);

    expect(filtered.length, 2);
    expect(
      filtered.any((i) => i is IOSSystemContextMenuItemLiveText),
      isFalse,
    );
  });

  test('an empty menu stays empty rather than throwing', () {
    expect(contextMenuButtonItemsWithoutScanText(const []), isEmpty);
    expect(systemContextMenuItemsWithoutScanText(const []), isEmpty);
  });

  testWidgets('AppInput wires the filter in, which is the actual gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: AppInput(
            controller: TextEditingController(),
            semanticLabel: 'A field',
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.contextMenuBuilder,
      same(textContextMenuWithoutScanText),
      reason: 'without this every field but the composer offers Scan Text',
    );
  });
}
