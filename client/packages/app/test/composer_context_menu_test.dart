// SPDX-License-Identifier: Apache-2.0
/// The composer field's context-menu fix: forcing the iOS 16+ system menu
/// to offer Paste for an image.
///
/// [systemContextMenuItemsWithForcedPaste] is pure, so its two cases (adds
/// the item, never duplicates it) need no platform channel and no device.
/// [ClipboardImageStatusNotifier] is proven at the same
/// `top.npcserver.slimm/clipboard_image` channel `composer_clipboard_image_
/// test.dart` already drives, with one property load-bearing enough to name
/// as its own test: it must never call the prompting `readImage`, only the
/// metadata-only `hasImage` - see `composer_context_menu.dart`'s doc comment
/// for why that distinction is the whole point of this fix.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/widgets/composer_context_menu.dart';

import 'composer_harness.dart';

const _channel = MethodChannel('top.npcserver.slimm/clipboard_image');

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('systemContextMenuItemsWithForcedPaste', () {
    test('adds the system Paste item when the clipboard holds an image', () {
      final items = systemContextMenuItemsWithForcedPaste(
        const [],
        clipboardHasImage: true,
      );
      expect(items, [isA<IOSSystemContextMenuItemPaste>()]);
    });

    test('adds nothing when the clipboard holds no image', () {
      final items = systemContextMenuItemsWithForcedPaste(
        const [],
        clipboardHasImage: false,
      );
      expect(items, isEmpty);
    });

    test('never duplicates a Paste item the defaults already offered', () {
      final items = systemContextMenuItemsWithForcedPaste(const [
        IOSSystemContextMenuItemPaste(),
      ], clipboardHasImage: true);
      expect(items, [isA<IOSSystemContextMenuItemPaste>()]);
    });

    test('leaves unrelated default items untouched', () {
      final items = systemContextMenuItemsWithForcedPaste(const [
        IOSSystemContextMenuItemCopy(),
      ], clipboardHasImage: true);
      expect(items, [
        isA<IOSSystemContextMenuItemCopy>(),
        isA<IOSSystemContextMenuItemPaste>(),
      ]);
    });
  });

  group('systemContextMenuItemsWithoutScanText', () {
    test('drops the Live Text (scan text) item', () {
      final items = systemContextMenuItemsWithoutScanText(const [
        IOSSystemContextMenuItemCopy(),
        IOSSystemContextMenuItemLiveText(),
        IOSSystemContextMenuItemPaste(),
      ]);
      expect(items, [
        isA<IOSSystemContextMenuItemCopy>(),
        isA<IOSSystemContextMenuItemPaste>(),
      ]);
    });

    test('leaves the list untouched when Live Text is not offered', () {
      final items = systemContextMenuItemsWithoutScanText(const [
        IOSSystemContextMenuItemCopy(),
      ]);
      expect(items, [isA<IOSSystemContextMenuItemCopy>()]);
    });

    test(
      'composes with forced paste: scan text stays gone, paste is added',
      () {
        final items = systemContextMenuItemsWithForcedPaste(
          systemContextMenuItemsWithoutScanText(const [
            IOSSystemContextMenuItemLiveText(),
          ]),
          clipboardHasImage: true,
        );
        expect(items, [isA<IOSSystemContextMenuItemPaste>()]);
      },
    );
  });

  group('contextMenuButtonItemsWithoutScanText', () {
    test('drops the liveTextInput button', () {
      final items = contextMenuButtonItemsWithoutScanText([
        const ContextMenuButtonItem(
          onPressed: null,
          type: ContextMenuButtonType.copy,
        ),
        const ContextMenuButtonItem(
          onPressed: null,
          type: ContextMenuButtonType.liveTextInput,
        ),
      ]);
      expect(items, [
        isA<ContextMenuButtonItem>().having(
          (item) => item.type,
          'type',
          ContextMenuButtonType.copy,
        ),
      ]);
    });

    test('leaves the list untouched when liveTextInput is not offered', () {
      final items = contextMenuButtonItemsWithoutScanText([
        const ContextMenuButtonItem(
          onPressed: null,
          type: ContextMenuButtonType.paste,
        ),
      ]);
      expect(items, hasLength(1));
      expect(items.single.type, ContextMenuButtonType.paste);
    });
  });

  group('ClipboardImageStatusNotifier', () {
    late List<String> calledMethods;

    setUp(() {
      calledMethods = [];
      _mock((call) async {
        calledMethods.add(call.method);
        return call.method == 'hasImage';
      });
    });

    tearDown(() => _mock(null));

    test('picks up the clipboard state on construction', () async {
      final notifier = ClipboardImageStatusNotifier();
      addTearDown(notifier.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(notifier.value, isTrue);
    });

    test('update never calls the prompting readImage, only the metadata-only '
        'hasImage (regression guard: this is the whole reason nothing here '
        'raises "Allow Paste?" on its own)', () async {
      final notifier = ClipboardImageStatusNotifier();
      addTearDown(notifier.dispose);

      await notifier.update();

      expect(calledMethods, everyElement('hasImage'));
      expect(calledMethods, isNot(contains('readImage')));
    });

    test('refreshes when the app resumes', () async {
      final notifier = ClipboardImageStatusNotifier();
      addTearDown(notifier.dispose);
      await Future<void>.delayed(Duration.zero);
      calledMethods.clear();

      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await Future<void>.delayed(Duration.zero);

      expect(calledMethods, ['hasImage']);
    });

    test('a disposed notifier ignores an in-flight update', () async {
      final notifier = ClipboardImageStatusNotifier();
      final update = notifier.update();
      notifier.dispose();

      await update;
      // Not throwing is the assertion: a disposed ValueNotifier raises on set.
    });
  });

  group('wired into the composer field', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => _mock(null));

    testWidgets(
      'the field carries a contextMenuBuilder rather than the default null '
      '(regression guard: this is what makes the fix reachable at all)',
      (tester) async {
        _mock((call) async => call.method == 'hasImage');
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          composerHarness(
            controller: controller,
            sends: Sends(),
            platform: TargetPlatform.iOS,
          ),
        );

        expect(
          tester.widget<TextField>(find.byType(TextField)).contextMenuBuilder,
          isNotNull,
        );
      },
    );
  });
}
