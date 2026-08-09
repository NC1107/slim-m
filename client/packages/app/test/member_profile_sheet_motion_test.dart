// SPDX-License-Identifier: Apache-2.0
/// `showMemberProfile`'s compact branch is a raw `showModalBottomSheet`, and
/// unlike the desktop popover a few lines below it (`showGeneralDialog`,
/// whose `transitionDuration` already reads `AppMotion.reduced` directly)
/// its own entrance is driven by a plain `AnimationController` Flutter owns.
/// That controller reads the platform's reduce-motion feature, never this
/// app's `MediaQuery` override - the same gap `sheet_test.dart` covers for
/// `showAppSheet`, on the one call site that bypasses it.
///
/// `member_profile_dismiss_test.dart` already forces reduce-motion on, but
/// only ever at the default (desktop-width) test window, so it exercises the
/// already-correct popover branch and never this one.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/member_presence.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/member_profile.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _other = api.UserProfile(
  id: 'user-maya',
  username: 'maya',
  displayName: 'maya',
  createdAt: 0,
);

Widget _openPage(BuildContext context, GoRouterState state) => Scaffold(
  body: Consumer(
    builder: (context, ref, _) => GestureDetector(
      onTap: () => showMemberProfile(
        context,
        ref,
        profile: _other,
        status: AppPresence.online,
      ),
      child: const Text('open'),
    ),
  ),
);

GoRouter _testRouter() => GoRouter(
  initialLocation: '/channels',
  routes: [GoRoute(path: '/channels', builder: _openPage)],
);

/// Pumps the compact popover at a phone width, [reduceMotion] applied the
/// same way `sheet_test.dart` applies it: `copyWith` on the ambient
/// `MediaQuery`, not a bare replacement, so the size a phone width already
/// set is not lost underneath it.
Future<void> _openCompact(
  WidgetTester tester, {
  required bool reduceMotion,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = SlimmDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      databaseProvider.overrideWith((ref) async => db),
      myPermissionsProvider.overrideWithValue(0),
      membersProvider.overrideWith((ref) async => [_other]),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: MaterialApp.router(
            theme: buildTheme(Brightness.light, AppTokens.light),
            routerConfig: _testRouter(),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
}

void main() {
  testWidgets(
    'the compact popover opens with no running animation under reduce motion',
    (tester) async {
      await _openCompact(tester, reduceMotion: true);
      await tester.pump();

      expect(find.byType(MemberProfileBody), findsOneWidget);
      expect(
        tester.hasRunningAnimations,
        isFalse,
        reason: 'nothing may keep ticking once the viewer has asked it not to',
      );
    },
  );

  testWidgets('the compact popover still animates by default', (tester) async {
    await _openCompact(tester, reduceMotion: false);
    await tester.pump();

    expect(
      tester.hasRunningAnimations,
      isTrue,
      reason:
          "a viewer who asked for nothing keeps the sheet's own stock "
          "entrance rather than this app's override collapsing it",
    );
    await tester.pumpAndSettle();
  });
}
