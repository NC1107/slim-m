// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The category header's own menu (design review note 8): move up/down's
/// boundary gating, and that collapse actually flips the stored fold state.
/// Rename and delete are already covered by `manage_category_sheet.dart`'s
/// own callers.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/collapsed_categories_preference.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/category_header_menu.dart';
import 'package:slimm_app/src/widgets/channel_category_drag.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _categories = [
  ChannelCategoryRow(id: 'cat-a', name: 'General', position: 0),
  ChannelCategoryRow(id: 'cat-b', name: 'Voice', position: 1),
];

({ProviderContainer container, List<http.Request> requests, SlimmDatabase db})
_setup() {
  final requests = <http.Request>[];
  SharedPreferences.setMockInitialValues({});
  final db = SlimmDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      preferencesProvider.overrideWith(
        (ref) => SharedPreferences.getInstance(),
      ),
      databaseProvider.overrideWith((ref) => db),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.method == 'PATCH' &&
                request.url.path.startsWith('/categories/')) {
              final id = request.url.path.split('/').last;
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              final existing = _categories.firstWhere((c) => c.id == id);
              return http.Response(
                jsonEncode({
                  'id': id,
                  'name': body['name'] as String? ?? existing.name,
                  'position': body['position'] as int? ?? existing.position,
                  'created_at': 0,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('{}', 404);
          }),
        );
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );
  return (container: container, requests: requests, db: db);
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  ChannelCategoryRow category,
) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: CategoryHeaderMenu(
            category: category,
            categories: _categories,
            collapsed: const {},
            label: Text(category.name),
          ),
        ),
      ),
    ),
  );
}

/// Both headers stacked as they render in the rail, so a drag from one's
/// grip can land on the other.
Future<void> _pumpBoth(WidgetTester tester, ProviderContainer container) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: Column(
            children: [
              for (final category in _categories)
                CategoryHeaderMenu(
                  category: category,
                  categories: _categories,
                  collapsed: const {},
                  label: Text(category.name),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tapAt(
    tester.getCenter(find.byType(CategoryHeaderMenu)),
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the first category offers no "Move up"', (tester) async {
    final setup = _setup();
    addTearDown(setup.container.dispose);
    addTearDown(setup.db.close);
    await _pump(tester, setup.container, _categories[0]);

    await _openMenu(tester);

    expect(find.text('Move category up'), findsNothing);
    expect(find.text('Move category down'), findsOneWidget);
  });

  testWidgets('the last category offers no "Move down"', (tester) async {
    final setup = _setup();
    addTearDown(setup.container.dispose);
    addTearDown(setup.db.close);
    await _pump(tester, setup.container, _categories[1]);

    await _openMenu(tester);

    expect(find.text('Move category up'), findsOneWidget);
    expect(find.text('Move category down'), findsNothing);
  });

  testWidgets(
    'moving the first category down swaps it past the second, one PATCH '
    'per category at its new position',
    (tester) async {
      final setup = _setup();
      addTearDown(setup.container.dispose);
      addTearDown(setup.db.close);
      await _pump(tester, setup.container, _categories[0]);

      await _openMenu(tester);
      await tester.tap(find.text('Move category down'));
      await tester.pumpAndSettle();

      final patches = setup.requests.where((r) => r.method == 'PATCH').toList();
      expect(patches, hasLength(2));
      final positions = {
        for (final r in patches)
          r.url.path.split('/').last:
              (jsonDecode(r.body) as Map<String, dynamic>)['position'],
      };
      expect(positions, {
        'cat-b': 0,
        'cat-a': 1,
      }, reason: 'cat-a moved past cat-b, so cat-b is now first');
    },
  );

  testWidgets(
    "dragging the first header's grip onto the second reorders exactly the "
    'way "Move category down" does - the channels never move, only the '
    'category list order',
    (tester) async {
      final setup = _setup();
      addTearDown(setup.container.dispose);
      addTearDown(setup.db.close);
      await _pumpBoth(tester, setup.container);

      final grip = find.byType(CategoryDragGrip).first;
      final target = find.byType(CategoryHeaderMenu).last;

      final gesture = await tester.startGesture(tester.getCenter(grip));
      await tester.pump();
      // Well into the target's bottom half - its center is an exact tie the side calculation resolves arbitrarily.
      await gesture.moveTo(tester.getBottomLeft(target) + const Offset(10, -2));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final patches = setup.requests.where((r) => r.method == 'PATCH').toList();
      expect(patches, hasLength(2));
      final positions = {
        for (final r in patches)
          r.url.path.split('/').last:
              (jsonDecode(r.body) as Map<String, dynamic>)['position'],
      };
      expect(positions, {'cat-b': 0, 'cat-a': 1});
    },
  );

  testWidgets('collapse toggles the stored fold state for that category '
      'only', (tester) async {
    final setup = _setup();
    addTearDown(setup.container.dispose);
    addTearDown(setup.db.close);
    await _pump(tester, setup.container, _categories[0]);

    await _openMenu(tester);
    expect(find.text('Collapse category'), findsOneWidget);
    await tester.tap(find.text('Collapse category'));
    await tester.pumpAndSettle();

    expect(setup.container.read(collapsedCategoriesProvider), {'cat-a'});
  });
}
