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
    'open, the divider reserves only its own hairline width in the row - '
    'nothing is held off the boundary to make room for a wider hit region',
    (tester) async {
      final s = setup();
      await pumpAtWidth(tester, s.container, 1400);

      final size = tester.getSize(find.byType(RailDragHandle));
      expect(
        size.width,
        1,
        reason:
            'backlog item 58: a reserved gap either side of the line - '
            'colour-matched or not - is what this fix removes',
      );

      await teardown(tester, s.container, s.db);
    },
  );

  testWidgets(
    'clicking just left of the line still toggles - the hit region reaches '
    "back into the rail's own already-blank edge rather than the reserved "
    'gap this replaced',
    (tester) async {
      final s = setup();
      await pumpAtWidth(tester, s.container, 1400);

      final line = tester.getCenter(find.byType(RailDragHandle));
      await tester.tapAt(line - const Offset(6, 0));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelRail), findsNothing);

      await teardown(tester, s.container, s.db);
    },
  );

  testWidgets(
    'clicking just right of the line does not toggle - a message row is '
    'opaque edge to edge in the transcript, so the hit region must not '
    'reach there',
    (tester) async {
      final s = setup();
      await pumpAtWidth(tester, s.container, 1400);

      final line = tester.getCenter(find.byType(RailDragHandle));
      await tester.tapAt(line + const Offset(6, 0));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelRail), findsOneWidget);

      await teardown(tester, s.container, s.db);
    },
  );

  testWidgets(
    'clicking further left than the rail already leaves blank does not '
    "toggle - the cap that keeps this from ever reaching the footer's "
    'settings button, which sits exactly at that edge',
    (tester) async {
      final s = setup();
      await pumpAtWidth(tester, s.container, 1400);

      final line = tester.getCenter(find.byType(RailDragHandle));
      await tester.tapAt(line - const Offset(10, 0));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelRail), findsOneWidget);

      await teardown(tester, s.container, s.db);
    },
  );

  testWidgets(
    'open, the semantics tree carries this control\'s label exactly once - '
    'dumped rather than inferred, since a leaked action bled onto an '
    'unrelated ancestor once before (backlog item 54)',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final s = setup();
      await pumpAtWidth(tester, s.container, 1400);

      final dump = tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep();
      expect('Collapse channel list'.allMatches(dump).length, 1, reason: dump);
      expect(find.bySemanticsLabel('Collapse channel list'), findsOneWidget);

      semantics.dispose();
      await teardown(tester, s.container, s.db);
    },
  );

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

  /// shell.md: the collapsed icon is the sole way back once the rail is
  /// gone, and it used to rest at `borderSubtle`, roughly 1.3:1 against the
  /// surface in both themes - well under WCAG 1.4.11's 3:1 floor for a UI
  /// component. `textSecondary` is already gated at the stricter 4.5:1 AA
  /// text floor by `design_system/test/contrast_test.dart`, so pinning the
  /// icon to that token, not the hairline border, is what this asserts.
  testWidgets('the collapsed icon does not rest at the hairline border color', (
    tester,
  ) async {
    final s = setup();
    await pumpAtWidth(tester, s.container, 1400);
    s.container.read(channelRailVisibleProvider.notifier).state = false;
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(AppIcons.sidebar));
    final tokens = AppTokens.light;
    expect(icon.color, tokens.textSecondary);
    expect(icon.color, isNot(tokens.borderSubtle));

    await teardown(tester, s.container, s.db);
  });

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
    "a real channel row's own right edge never falls inside the divider's "
    "widened reach - the two are pinned to the same AppSpacing.s8, and "
    "channel_rail.dart's own row-list padding is a bare literal 8 with "
    "nothing tying it to that token",
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
      await pumpAtWidth(tester, s.container, 1400);
      await tester.pumpAndSettle();

      final railRect = tester.getRect(find.byType(ChannelRail));
      final rowRect = tester.getRect(find.byType(AppListRow).first);
      final reachLeftEdge = railRect.right - AppSpacing.s8;

      expect(
        rowRect.right,
        lessThanOrEqualTo(reachLeftEdge),
        reason:
            "if channel_rail.dart's own row padding ever drifts from "
            "AppSpacing.s8, a real row's own tap target would sit under "
            "the divider's widened hit area and lose its own right edge "
            'to a rail-collapse tap instead of a channel switch',
      );

      await teardown(tester, s.container, s.db);
    },
  );

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
