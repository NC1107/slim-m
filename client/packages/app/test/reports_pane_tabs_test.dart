// SPDX-License-Identifier: Apache-2.0
/// The History tab beside the open-reports queue, exercised through the real
/// `ReportsScreen`: switching tabs shows the other feed without disturbing
/// the one left behind. `moderation_history_controller_test.dart` covers the
/// controller's own cursor, permission-refusal and live-update behavior in
/// isolation; this is the one place that proves the tab itself is wired to
/// it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'report_card_harness.dart';

String _auditJson(String id) =>
    '{"kind":"audit_log","id":"$id","actor_id":"mod-1",'
    '"subject_id":"user-1","action":"remove","reason":null,'
    '"until":null,"created_at":0}';

void main() {
  testWidgets(
    'switching to History shows its own feed without touching the open '
    'queue',
    (tester) async {
      await pumpReports(
        tester,
        reports: [],
        history: [_auditJson('a1')],
        profiles: {'mod-1': 'Mod One', 'user-1': 'Some User'},
      );

      expect(find.text('The queue is empty.'), findsOneWidget);
      expect(find.text('Some User'), findsNothing);

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(
        find.text('Some User'),
        findsOneWidget,
        reason: 'the audit entry\'s subject, once its History tab is shown',
      );
      expect(find.text('The queue is empty.'), findsNothing);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        find.text('The queue is empty.'),
        findsOneWidget,
        reason:
            'switching back must not have lost the open queue\'s own '
            'state',
      );
    },
  );
}
