// SPDX-License-Identifier: Apache-2.0
/// Tests for the message row's context menu: which items a caller's flags
/// actually put on screen, and the placement rules the menu has to hold.
///
/// Split out of `message_row_test.dart`, which had grown past this repo's
/// hard file limit. The seam is the widget: everything here goes through
/// [MessageContextMenuRegion] rather than through how a row renders.
/// `message_context_menu_scroll_test.dart` covers the one behaviour that
/// needs a scrollable around it.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/animated_menu_portal.dart';
import 'package:slimm_app/src/widgets/emoji_picker.dart';
import 'package:slimm_app/src/widgets/emoji_picker_grid.dart';
import 'package:slimm_app/src/widgets/message_context_menu.dart';
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row_harness.dart';

/// The glyph in the picker's first cell, read off the grid rather than
/// hardcoded: the catalog comes from the third-party `emojis` package, so a
/// package bump reorders it and a fixed literal would fail for a reason that
/// has nothing to do with the behaviour under test.
String _firstGridGlyph(WidgetTester tester) =>
    tester.widget<EmojiGrid>(find.byType(EmojiGrid)).emoji.first.token;

void main() {
  Widget row(MessageActions actions, {ValueChanged<String>? onPickReaction}) =>
      MessageRow(
        message: message(),
        grouped: false,
        showNewDivider: false,
        knownUsernames: const {},
        onRetry: () {},
        onDiscard: () {},
        onPickReaction: onPickReaction ?? (_) {},
        onReactionTap: (_) {},
        onVote: (_) {},
        actions: actions,
        editing: false,
        onSubmitEdit: (_) {},
        onCancelEdit: () {},
      );

  Widget rowWith(
    MessageActions actions, {
    ValueChanged<String>? onPickReaction,
  }) => harness(row(actions, onPickReaction: onPickReaction));

  // Press the leading avatar, not the message text: in this bare harness,
  // with no bounding ListView, an ancestor recognizer swallows the text press.
  Offset pressPoint(WidgetTester tester) =>
      tester.getTopLeft(find.byType(MessageContextMenuRegion)) +
      const Offset(30, 30);

  testWidgets('long-press offers only what the caller allowed, plus copy', (
    tester,
  ) async {
    await tester.pumpWidget(rowWith(noActions));

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    expect(
      find.text('Copy text'),
      findsOneWidget,
      reason: 'copy is never gated',
    );
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Pin'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('a right-click opens the same menu edit allows', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      rowWith(
        MessageActions(
          canReply: false,
          onReply: noop,
          canEdit: true,
          onEdit: () => edited = true,
          canDelete: false,
          onDelete: noop,
          canManagePins: false,
          pinned: false,
          onTogglePin: noop,
          canReport: false,
          onReport: noop,
          canBlockAuthor: false,
          onBlockAuthor: noop,
          canOpenThread: false,
          onOpenThread: noop,
        ),
      ),
    );

    await tester.tapAt(
      pressPoint(tester),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    expect(edited, isTrue);
  });

  testWidgets('reply in thread is offered when allowed and reports its tap', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      rowWith(
        MessageActions(
          canReply: false,
          onReply: noop,
          canEdit: false,
          onEdit: noop,
          canDelete: false,
          onDelete: noop,
          canManagePins: false,
          pinned: false,
          onTogglePin: noop,
          canReport: false,
          onReport: noop,
          canBlockAuthor: false,
          onBlockAuthor: noop,
          canOpenThread: true,
          onOpenThread: () => opened = true,
        ),
      ),
    );

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reply in thread'));
    expect(opened, isTrue);
  });

  testWidgets('reply in thread is absent when the caller disallows it', (
    tester,
  ) async {
    await tester.pumpWidget(rowWith(noActions));

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    expect(find.text('Reply in thread'), findsNothing);
  });

  testWidgets('the pin item reads "Unpin" once already pinned', (tester) async {
    await tester.pumpWidget(
      rowWith(
        const MessageActions(
          canReply: false,
          onReply: noop,
          canEdit: false,
          onEdit: noop,
          canDelete: false,
          onDelete: noop,
          canManagePins: true,
          pinned: true,
          onTogglePin: noop,
          canReport: false,
          onReport: noop,
          canBlockAuthor: false,
          onBlockAuthor: noop,
          canOpenThread: false,
          onOpenThread: noop,
        ),
      ),
    );

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    expect(find.text('Unpin'), findsOneWidget);
    expect(find.text('Pin'), findsNothing);
  });

  testWidgets('delete is in danger tone and reports its tap', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      rowWith(
        MessageActions(
          canReply: false,
          onReply: noop,
          canEdit: false,
          onEdit: noop,
          canDelete: true,
          onDelete: () => deleted = true,
          canManagePins: false,
          pinned: false,
          onTogglePin: noop,
          canReport: false,
          onReport: noop,
          canBlockAuthor: false,
          onBlockAuthor: noop,
          canOpenThread: false,
          onOpenThread: noop,
        ),
      ),
    );

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));

    expect(deleted, isTrue);
  });

  // SlimmApi.report once had no call site at all, despite the endpoint and a
  // full admin triage screen existing. Nothing gated that regressing.
  testWidgets('a message not authored by the caller offers Report and Block', (
    tester,
  ) async {
    var reported = false;
    var blocked = false;
    await tester.pumpWidget(
      rowWith(
        MessageActions(
          canReply: false,
          onReply: noop,
          canEdit: false,
          onEdit: noop,
          canDelete: false,
          onDelete: noop,
          canManagePins: false,
          pinned: false,
          onTogglePin: noop,
          canReport: true,
          onReport: () => reported = true,
          canBlockAuthor: true,
          onBlockAuthor: () => blocked = true,
          canOpenThread: false,
          onOpenThread: noop,
        ),
      ),
    );

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    expect(find.text('Report message'), findsOneWidget);
    expect(find.text('Block user'), findsOneWidget);

    await tester.tap(find.text('Report message'));
    await tester.pumpAndSettle();
    expect(reported, isTrue);

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    expect(blocked, isTrue);
  });

  // The bug: the only add-reaction control was revealed by a MouseRegion,
  // so touch could not reach it. No mouse pointer here is the assertion.
  testWidgets('a long-press reaches the reaction picker with no pointer', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      rowWith(noActions, onPickReaction: (e) => picked = e),
    );

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();
    expect(find.text('Add reaction'), findsOneWidget);

    await tester.tap(find.text('Add reaction'));
    await tester.pumpAndSettle();
    expect(
      find.byType(EmojiPickerPanel),
      findsOneWidget,
      reason: 'the menu item should open the picker sheet',
    );

    final glyph = _firstGridGlyph(tester);
    await tester.tap(
      find.descendant(of: find.byType(EmojiGrid), matching: find.text(glyph)),
    );
    await tester.pumpAndSettle();
    expect(picked, glyph);
    expect(
      find.byType(EmojiPickerPanel),
      findsNothing,
      reason: 'picking should close the sheet',
    );
  });

  testWidgets('a long-press does not mount the hover-only picker button', (
    tester,
  ) async {
    await tester.pumpWidget(rowWith(noActions));

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    expect(find.byType(AppMenu), findsOneWidget);
    expect(
      find.byType(EmojiPickerButton),
      findsNothing,
      reason: 'pinning on touch only mounts a button the menu covers',
    );
  });

  testWidgets('a right-click still pins the row, so it cannot reflow', (
    tester,
  ) async {
    await tester.pumpWidget(rowWith(noActions));

    await tester.tapAt(
      pressPoint(tester),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(EmojiPickerButton),
      findsOneWidget,
      reason: 'the pointer path keeps its revealed controls mounted',
    );
  });

  // Why the menu is placed once rather than following the row: a scroll
  // begins with a press outside it, and that closes it first.
  testWidgets('a press outside closes the menu before it can be scrolled', (
    tester,
  ) async {
    await tester.pumpWidget(rowWith(noActions));

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();
    expect(find.byType(AppMenu), findsOneWidget);

    final outside = await tester.startGesture(const Offset(700, 550));
    await tester.pump();
    // The press-down starts the exit; the fading remains must not eat input.
    final surface = tester.widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(AnimatedMenuSurface),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(surface.ignoring, isTrue);
    // Gone before the finger ever lifts, so the close rode the down event.
    await tester.pumpAndSettle();
    expect(find.byType(AppMenu), findsNothing);
    await outside.up();
  });

  // Six touch-height items plus dividers is taller than the space below a
  // message near the bottom of the screen, and the menu used to run off it.
  testWidgets('a menu opened low on the screen stays inside the viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        Column(
          children: [
            const Spacer(),
            row(
              const MessageActions(
                canReply: false,
                onReply: noop,
                canEdit: true,
                onEdit: noop,
                canDelete: true,
                onDelete: noop,
                canManagePins: true,
                pinned: false,
                onTogglePin: noop,
                canReport: true,
                onReport: noop,
                canBlockAuthor: true,
                onBlockAuthor: noop,
                canOpenThread: false,
                onOpenThread: noop,
              ),
            ),
          ],
        ),
      ),
    );

    await tester.longPressAt(pressPoint(tester));
    await tester.pumpAndSettle();

    final menu = tester.getRect(find.byType(AppMenu));
    final screen = tester.getRect(find.byType(MaterialApp));
    expect(menu.bottom, lessThanOrEqualTo(screen.bottom));
    expect(menu.top, greaterThanOrEqualTo(screen.top));
    expect(find.text('Delete'), findsOneWidget);
  });
}
