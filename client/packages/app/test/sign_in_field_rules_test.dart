// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The username and password rules are said before a submission fails, but
/// only while creating an account; a rejection that names a field lands on
/// that field.
///
/// Both halves guard the same complaint: the rules existed only on the server,
/// so the first time a newcomer heard about them was after being told no. The
/// helper text is the part that prevents the failure; the routing is the part
/// that makes the failure legible when it still happens.
///
/// The password helper is checked against the server's own wording, read from
/// the shared fixture `support/onboarding_error_strings.dart` loads, so a
/// change to the length rule cannot leave the guidance quietly stating the old
/// minimum.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/sign_in_credential_fields.dart';
import 'package:slimm_app/src/screens/sign_in_error.dart';
import 'package:slimm_app/src/screens/sign_in_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import 'support/onboarding_error_strings.dart';

http.Client _quietProbe() => MockClient((request) async {
  if (request.method == 'GET' && request.url.path == '/version') {
    return http.Response(
      jsonEncode({'name': 'slim-m', 'version': '0.10.0', 'protocol': 1}),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
  return http.Response('{}', 200);
});

Future<void> _pumpSignIn(WidgetTester tester) async {
  final client = _quietProbe();
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      serverUrlProvider.overrideWith(
        (ref) => Uri.parse('https://example.test'),
      ),
      probeApiProvider.overrideWithValue(
        (baseUrl) => SlimmApi(baseUrl: baseUrl, httpClient: client),
      ),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: ref.watch(serverUrlProvider),
          session: ref.watch(sessionProvider),
          httpClient: client,
        );
        ref.onDispose(api.close);
        return api;
      }),
    ],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const SignInScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Future<void> toCreateAccount(WidgetTester tester) async {
    await tester.tap(find.text('Create an account instead'));
    await tester.pumpAndSettle();
  }

  group('while signing in, no field states a creation rule', () {
    testWidgets('username', (tester) async {
      await _pumpSignIn(tester);

      expect(find.text(usernameRule), findsNothing);
    });

    testWidgets('password', (tester) async {
      await _pumpSignIn(tester);

      expect(find.text(passwordRule), findsNothing);
    });

    testWidgets('display name is not asked for at all', (tester) async {
      await _pumpSignIn(tester);

      expect(find.text('Display name'), findsNothing);
      expect(find.text(displayNameHelper), findsNothing);
    });

    testWidgets('the screen carries no helper text on any field', (
      tester,
    ) async {
      await _pumpSignIn(tester);

      expect(find.textContaining('characters'), findsNothing);
      expect(find.textContaining('Defaults to'), findsNothing);
    });
  });

  group('while creating an account, each rule is said before submitting', () {
    testWidgets('username: the charset and the length are both enforced, so '
        'both are said', (tester) async {
      await _pumpSignIn(tester);
      await toCreateAccount(tester);

      expect(
        find.text('Letters, digits, _ . and - only. Up to 32 characters.'),
        findsOneWidget,
      );
    });

    testWidgets('password minimum', (tester) async {
      await _pumpSignIn(tester);
      await toCreateAccount(tester);

      expect(find.text('At least 8 characters.'), findsOneWidget);
    });

    testWidgets('display name says what it is and what it defaults to', (
      tester,
    ) async {
      await _pumpSignIn(tester);
      await toCreateAccount(tester);

      expect(find.text(displayNameHelper), findsOneWidget);
    });

    testWidgets('going back to sign in takes the rules away again', (
      tester,
    ) async {
      await _pumpSignIn(tester);
      await toCreateAccount(tester);
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();

      expect(find.text(usernameRule), findsNothing);
      expect(find.text(passwordRule), findsNothing);
    });
  });

  test(
    'the password helper states the minimum the server actually enforces',
    () {
      final strings = OnboardingErrorStrings.load();
      final minimum = RegExp(
        r'\d+',
      ).firstMatch(strings.passwordLengthError)?.group(0);

      expect(
        minimum,
        isNotNull,
        reason: 'the wire message is expected to carry the length rule',
      );
      expect(
        passwordRule,
        contains(minimum!),
        reason:
            'the helper and the rejection must agree; if this fails the server '
            'rule moved and sign_in_screen.dart still advertises the old one',
      );
    },
  );

  test('a 400 that names a field lands on that field, not on the form', () {
    expect(
      signInErrorFor(
        const BadRequestException('password must be 8 to 1024 characters'),
      ).$1,
      SignInErrorField.password,
    );
    expect(
      signInErrorFor(
        const BadRequestException('username must be 1 to 32 characters'),
      ).$1,
      SignInErrorField.username,
    );
    expect(
      signInErrorFor(
        const BadRequestException(
          'username may contain only letters, digits, and _ . -',
        ),
      ).$1,
      SignInErrorField.username,
      reason: 'the charset rejection is the same field as the length one',
    );
  });

  test('a 400 that names nothing recognisable stays on the form', () {
    expect(
      signInErrorFor(const BadRequestException('invite code is not usable')).$1,
      SignInErrorField.form,
      reason: 'no single input owns this, so it belongs to the form',
    );
  });

  test('the message itself is preserved whichever field it lands on', () {
    expect(
      signInErrorFor(
        const BadRequestException('password must be 8 to 1024 characters'),
      ).$2,
      'Password must be 8 to 1024 characters.',
      reason: 'error grammar 03: keep the content of the thing that failed',
    );
  });
}
