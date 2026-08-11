// SPDX-License-Identifier: Apache-2.0
/// Whether a long value on the report card actually fits at phone width,
/// split out of `report_card_test.dart` for the line budget - the same
/// split that file's own doc comment already draws for the quick actions.
///
/// A real overflow found only once the capture harness actually gave the
/// report fetch enough frames to resolve (see CLAUDE.md, 2026-08-11): the
/// reporter row's `Text` sat in a bare `Row` beside a `Spacer`, so a long
/// display name pushed the row 85 logical pixels past a phone-width card
/// rather than truncating. Geometry, not presence: `find.text` would keep
/// finding the label even while its `RenderFlex` overflowed, so these read
/// the label's real, laid-out rect instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_card_harness.dart';
import 'support/geometry.dart';

void main() {
  testWidgets(
    'a long reporter display name ellipsizes rather than overflowing at '
    'phone width',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const longName = 'Christoph Bartholomew Fitzgerald-Huang III';
      await pumpReports(
        tester,
        reports: [
          reportJson(
            id: 'report-long-reporter',
            subjectKind: 'message',
            subjectId: 'message-3',
            reporterId: 'reporter-long',
            channelId: 'channel-1',
            snapshot: 'go away',
          ),
        ],
        profiles: {'reporter-long': longName},
      );

      final label = find.text(longName);
      expect(label, findsOneWidget);
      expectClearOfEdge(
        tester,
        label,
        GeometryEdge.right,
        reason:
            'the reporter label must stay clear of the viewport edge, '
            'not merely exist somewhere in the tree',
      );
      expect(tester.widget<Text>(label).overflow, TextOverflow.ellipsis);
    },
  );
}
