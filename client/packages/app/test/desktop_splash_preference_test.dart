// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The desktop splash on/off and duration preferences: both default to the
/// existing behaviour (on, standard = 900ms), a choice persists and restores,
/// an unknown stored value degrades to the default, and [SplashDurationX]
/// maps each named choice to a concrete, distinct duration with [standard]
/// tied to [minSplashDuration] itself.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/desktop/splash_floor.dart';
import 'package:slimm_app/src/providers/desktop_splash_preference.dart';
import 'package:slimm_app/src/providers/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWith(
          (ref) => SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('SplashEnabledController', () {
    test('defaults to on, so it changes nothing on its own', () {
      expect(container().read(splashEnabledControllerProvider), isTrue);
    });

    test('selecting off persists, and restore reads it back', () async {
      final c = container();
      await c.read(splashEnabledControllerProvider.notifier).select(false);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          desktopSplashEnabledKey,
        ),
        isFalse,
      );

      final c2 = container();
      await c2.read(splashEnabledControllerProvider.notifier).restore();
      expect(c2.read(splashEnabledControllerProvider), isFalse);
    });

    test('turning it back on persists too, not just turning it off', () async {
      SharedPreferences.setMockInitialValues({desktopSplashEnabledKey: false});
      final c = container();
      await c.read(splashEnabledControllerProvider.notifier).select(true);

      final c2 = container();
      await c2.read(splashEnabledControllerProvider.notifier).restore();
      expect(c2.read(splashEnabledControllerProvider), isTrue);
    });
  });

  group('SplashDurationController', () {
    test('defaults to standard, so it changes nothing on its own', () {
      expect(
        container().read(splashDurationControllerProvider),
        SplashDuration.standard,
      );
    });

    test('every named choice honours its own concrete duration', () {
      expect(SplashDuration.brief.duration, const Duration(milliseconds: 500));
      expect(SplashDuration.standard.duration, minSplashDuration);
      expect(SplashDuration.long.duration, const Duration(milliseconds: 1500));
    });

    test('standard is minSplashDuration itself, so the two cannot drift '
        'apart', () {
      expect(
        SplashDuration.standard.duration,
        const Duration(milliseconds: 900),
      );
    });

    test('only standard names itself as the default in its label', () {
      expect(SplashDuration.standard.label, contains('default'));
      expect(SplashDuration.brief.label, isNot(contains('default')));
      expect(SplashDuration.long.label, isNot(contains('default')));
    });

    test('selecting persists, and restore reads it back', () async {
      final c = container();
      await c
          .read(splashDurationControllerProvider.notifier)
          .select(SplashDuration.long);
      expect(
        (await SharedPreferences.getInstance()).getString(
          desktopSplashDurationKey,
        ),
        'long',
      );

      final c2 = container();
      await c2.read(splashDurationControllerProvider.notifier).restore();
      expect(c2.read(splashDurationControllerProvider), SplashDuration.long);
    });

    test('an unknown stored value degrades to the default', () async {
      SharedPreferences.setMockInitialValues({
        desktopSplashDurationKey: 'glacial',
      });
      final c = container();
      await c.read(splashDurationControllerProvider.notifier).restore();
      expect(c.read(splashDurationControllerProvider), SplashDuration.standard);
    });
  });

  group('splashFloorFor', () {
    test('off means Duration.zero, no dwell at all, regardless of the '
        'stored duration', () {
      for (final duration in SplashDuration.values) {
        expect(
          splashFloorFor(enabled: false, duration: duration),
          Duration.zero,
          reason: '$duration must not matter once the splash is off',
        );
      }
    });

    test('on means the chosen duration, distinctly, for every choice', () {
      expect(
        splashFloorFor(enabled: true, duration: SplashDuration.brief),
        SplashDuration.brief.duration,
      );
      expect(
        splashFloorFor(enabled: true, duration: SplashDuration.standard),
        SplashDuration.standard.duration,
      );
      expect(
        splashFloorFor(enabled: true, duration: SplashDuration.long),
        SplashDuration.long.duration,
      );
    });

    test('on with standard is exactly the pre-existing minSplashDuration', () {
      expect(
        splashFloorFor(enabled: true, duration: SplashDuration.standard),
        minSplashDuration,
      );
    });
  });
}
