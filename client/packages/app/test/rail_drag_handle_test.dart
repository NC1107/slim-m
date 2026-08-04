// SPDX-License-Identifier: Apache-2.0
/// Tests for the handle that replaced the header's rail-collapse button
/// (#256's toggle) and then replaced drag-to-resize with a plain click
/// (backlog item 54): tap the rail's own edge to open or close it.
///
/// The hard requirement is discoverability: a collapsed rail with nothing
/// visible to click is a trap, so the collapsed-state test below asserts the
/// glyph both renders and actually restores the rail through its published
/// semantic action, not merely that an icon exists somewhere on screen.
///
/// The header's own "the button is gone" regression lives beside its other
/// tests, in `channel_header_test.dart`, which already carries the harness a
/// bare `ChannelHeader` needs (a signed-in session and a pin-list stub).
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/channel_rail.dart';
import 'package:slimm_app/src/widgets/channel_rail_drawer.dart';
import 'package:slimm_app/src/widgets/rail_drag_handle.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import 'home_shell_harness.dart';

void main() {
  testWidgets('clicking the handle collapses the rail, and clicking it '
      'again restores it', (tester) async {
    final s = setup();
    await pumpAtWidth(tester, s.container, 1400);
    expect(find.byType(ChannelRail), findsOneWidget);

    await tester.tap(find.byType(RailDragHandle));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelRail), findsNothing);

    await tester.tap(find.byType(RailDragHandle));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelRail), findsOneWidget);

    await teardown(tester, s.container, s.db);
  });

  testWidgets('the visible line is a plain hairline divider, never a filled '
      'bar', (tester) async {
    final s = setup();
    await pumpAtWidth(tester, s.container, 1400);

    final divider = tester.widget<VerticalDivider>(
      find.byType(VerticalDivider),
    );
    expect(
      divider.width,
      1,
      reason:
          'backlog item 54: a thick grab bar reads as a resize handle, '
          'not a toggle',
    );

    await teardown(tester, s.container, s.db);
  });

  testWidgets(
    'collapsed, a real glyph stays on screen, and the semantic action a '
    'screen reader or the keyboard would use really restores the rail - '
    'the mutation that matters is deleting either half of this',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final s = setup();
      await pumpAtWidth(tester, s.container, 1400);

      s.container.read(channelRailVisibleProvider.notifier).state = false;
      await tester.pumpAndSettle();
      expect(find.byType(ChannelRail), findsNothing);

      // Discoverable: a real, labelled control is on screen, not a blank gap.
      expect(find.byIcon(AppIcons.sidebar), findsOneWidget);
      expect(find.bySemanticsLabel('Expand channel list'), findsOneWidget);

      // Functional: the published action is what actually restores the rail, not merely a label sitting on an inert node.
      final node = tester.getSemantics(find.byType(RailDragHandle));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChannelRail), findsOneWidget);

      semantics.dispose();
      await teardown(tester, s.container, s.db);
    },
  );

  testWidgets('collapsing survives a channel switch, the same session-only '
      'persistence the provider already had', (tester) async {
    final s = setup();
    await pumpAtWidth(tester, s.container, 1400);

    await tester.tap(find.byType(RailDragHandle));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelRail), findsNothing);

    // A fresh pump, as a channel switch causes, must not readopt the default.
    await pumpAtWidth(tester, s.container, 1400, location: '/channels/c1');
    expect(find.byType(ChannelRail), findsNothing);

    await teardown(tester, s.container, s.db);
  });

  testWidgets(
    'the compact drawer from #301 is untouched: no rail handle at compact '
    'width, and the edge-swipe drawer still opens the rail',
    (tester) async {
      final s = setup(httpClient: quietClient(), signedIn: true);
      await MessageStore(s.db).upsertChannels([
        const api.Channel(
          id: 'c1',
          name: 'general',
          kind: 'text',
          createdAt: 0,
        ),
      ]);
      await pumpAtWidth(tester, s.container, 500, location: '/channels/c1');
      expect(
        find.byType(RailDragHandle),
        findsNothing,
        reason: 'compact never docks the rail, so there is no edge to click',
      );

      // Off-screen until dragged (#301's own suite covers the drag itself).
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.drawer, isA<CompactChannelRailDrawer>());

      await teardown(tester, s.container, s.db);
    },
  );
}
