// SPDX-License-Identifier: Apache-2.0
/// The everyone role offers no way to assign it, the same way it already
/// offers no way to delete it: every member holds it already, so a grant
/// would be a no-op the sheet next door has to filter out anyway.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/screens/admin/roles_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// [RolesScreen] stays live to role changes through `roleChangeWatcherProvider`,
/// which needs a [SyncController] to read; this one opens no real socket.
class _NoopSyncController extends SyncController {
  _NoopSyncController(super.ref);

  @override
  Future<void> start() async {}
}

api.Role _role(String id, String name, {bool everyone = false}) => api.Role(
  id: id,
  name: name,
  permissions: everyone ? Perm.viewChannel : Perm.manageMessages,
  isEveryone: everyone,
  createdAt: 0,
);

Future<void> _pump(WidgetTester tester, List<api.Role> roles) async {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      syncControllerProvider.overrideWith(_NoopSyncController.new),
      rolesProvider.overrideWith((ref) async => roles),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const RolesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the everyone role offers no Assign', (tester) async {
    await _pump(tester, [
      _role('role-everyone', '@everyone', everyone: true),
      _role('role-mod', 'mod'),
    ]);

    expect(
      find.bySemanticsLabel('Assign @everyone to members'),
      findsNothing,
      reason: 'every member already holds it, so granting it is a no-op',
    );
    expect(find.bySemanticsLabel('Assign mod to members'), findsOneWidget);
  });
}
