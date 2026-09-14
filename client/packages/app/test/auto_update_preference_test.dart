// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The stored answer to "keep slim-m up to date automatically?".
///
/// Three states, and the third is the point: until somebody answers, the
/// preference is absent rather than false, which is what lets the splash and
/// the signup screen tell "said no" from "never asked".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/auto_update_preference.dart';
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

  test('an install nobody has asked has no answer, not a false one', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(loadAutoUpdatePreference(prefs), isNull);
  });

  test('a stored no reads back as no, not as unanswered', () async {
    SharedPreferences.setMockInitialValues({autoUpdateKey: false});
    final prefs = await SharedPreferences.getInstance();
    expect(loadAutoUpdatePreference(prefs), isFalse);
  });

  test('setting it persists and shows up in the provider', () async {
    final c = container();
    await c.read(autoUpdateProvider.notifier).set(true);

    expect(c.read(autoUpdateProvider), isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(autoUpdateKey),
      isTrue,
    );
  });

  test('a stored answer is restored into the provider', () async {
    SharedPreferences.setMockInitialValues({autoUpdateKey: true});
    final c = container();
    // Reading builds the controller; its load resolves a microtask later, long before anything reads it for real.
    expect(c.read(autoUpdateProvider), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(autoUpdateProvider), isTrue);
  });

  test('turning it back off persists too', () async {
    SharedPreferences.setMockInitialValues({autoUpdateKey: true});
    final c = container();
    await c.read(autoUpdateProvider.notifier).set(false);

    expect(c.read(autoUpdateProvider), isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(autoUpdateKey),
      isFalse,
    );
  });
}
