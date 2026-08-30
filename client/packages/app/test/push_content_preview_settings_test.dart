// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Persistence for the "show message text on your lock screen" toggle, the
/// same shape `notification_sound_settings.dart`'s own tests would cover if
/// that file had a dedicated test of its own - this one exists mainly
/// because [PushContentPreviewController.currentValue] is load-bearing for
/// `push_controller_test.dart`'s `include_content` assertions and deserves
/// its own direct proof that it awaits the real persisted value rather than
/// the in-memory default.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/push_content_preview_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to off, matching the server\'s own default', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final value = await container
        .read(pushContentPreviewSettingsProvider.notifier)
        .currentValue();
    expect(value, isFalse);
  });

  test('turning it on persists, and currentValue reports it back', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      pushContentPreviewSettingsProvider.notifier,
    );
    await controller.setEnabled(true);

    expect(await controller.currentValue(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(pushIncludeContentKey), isTrue);
  });

  test('a previously-persisted true is what a fresh controller reports, not '
      'the in-memory false default it starts with', () async {
    SharedPreferences.setMockInitialValues({pushIncludeContentKey: true});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // No await before the read: currentValue() must await its own load.
    final value = await container
        .read(pushContentPreviewSettingsProvider.notifier)
        .currentValue();
    expect(value, isTrue);
  });

  test('a failed local-storage read still answers false rather than hanging '
      'PushController.register() forever', () async {
    final container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWith((ref) async {
          throw StateError('local storage unavailable');
        }),
      ],
    );
    addTearDown(container.dispose);

    final value = await container
        .read(pushContentPreviewSettingsProvider.notifier)
        .currentValue();
    expect(value, isFalse);
  });
}
