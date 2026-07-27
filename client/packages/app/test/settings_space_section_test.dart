// SPDX-License-Identifier: Apache-2.0
/// The settings screen's "Space" group must be gated on what `GET /me`
/// actually reports, not shown and left to answer 403: a caller with none of
/// the gating bits should see no Space group at all, and a caller with one
/// bit should see only the row that bit unlocks.
///
/// Where the three groups sit relative to each other is
/// `settings_taxonomy_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/permissions.dart';

import 'settings_harness.dart';

void main() {
  setUpAll(mockAppVersion);

  testWidgets('an ordinary member with none of the gating bits sees no '
      'Space group at all', (tester) async {
    await pumpSettings(tester, 0);

    expect(find.text('Space'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Invites'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
    expect(find.text('Emoji'), findsNothing);
  });

  testWidgets('MANAGE_MESSAGES alone unlocks only the reports row', (
    tester,
  ) async {
    await pumpSettings(tester, Perm.manageMessages);

    expect(find.text('Space'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Invites'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
  });

  testWidgets('CREATE_INVITE alone unlocks only the invites row', (
    tester,
  ) async {
    await pumpSettings(tester, Perm.createInvite);

    expect(find.text('Invites'), findsOneWidget);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
  });

  testWidgets(
    'MANAGE_ROLES alone unlocks both the roles and channel permissions '
    'rows together, since one screen sets up targets the other edits',
    (tester) async {
      await pumpSettings(tester, Perm.manageRoles);

      expect(find.text('Roles'), findsOneWidget);
      expect(find.text('Channel permissions'), findsOneWidget);
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Invites'), findsNothing);
    },
  );

  /// MANAGE_SERVER is the bit the emoji endpoints themselves enforce
  /// (`require_manage_server` in `crates/slimm-server/src/http/emoji.rs`), so
  /// it is the bit the row is gated on. It unlocks nothing else: a caller who
  /// can change what the deployment is cannot thereby read the report queue.
  testWidgets('MANAGE_SERVER alone unlocks only the emoji row', (tester) async {
    await pumpSettings(tester, Perm.manageServer);

    expect(find.text('Space'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Invites'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
  });

  testWidgets('MANAGE_ROLES does not bring the emoji row with it', (
    tester,
  ) async {
    await pumpSettings(tester, Perm.manageRoles);

    expect(find.text('Emoji'), findsNothing);
  });

  /// The server resolves ADMINISTRATOR into every bit before `/me` ever
  /// answers (see `evaluate()`'s bypass in permissions.rs), so the wire value
  /// a real administrator's client receives already has every bit set; this
  /// mock mirrors that resolved value rather than sending the lone
  /// ADMINISTRATOR bit and asking the client to re-derive the bypass itself,
  /// which it deliberately does not do.
  testWidgets('an administrator sees every row', (tester) async {
    await pumpSettings(tester, allPermissionBits);

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Invites'), findsOneWidget);
    expect(find.text('Roles'), findsOneWidget);
    expect(find.text('Channel permissions'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
  });
}
