// SPDX-License-Identifier: Apache-2.0
/// Tests for the message row: grouping must be visible in what actually
/// renders (the avatar and the gutter timestamp), not just in the flag
/// passed in, since that flag is exactly what a caller could get backwards.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/emoji_picker.dart';
import 'package:slimm_app/src/widgets/message_context_menu.dart';
import 'package:slimm_app/src/widgets/message_edit_field.dart';
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

Message _message({
  String id = 'm1',
  String? authorId = 'author-1',
  String? authorDisplayName = 'Priya',
  int createdAt = 1700000000000,
  int? editedAt,
  bool pending = false,
  bool failed = false,
}) => Message(
  id: id,
  channelId: 'c1',
  authorId: authorId,
  authorDisplayName: authorDisplayName,
  seq: 5,
  content: 'hello there',
  createdAt: createdAt,
  editedAt: editedAt,
  pending: pending,
  failed: failed,
);

void _noop() {}

/// Every item hidden. Most tests here care about nothing the context menu
/// does, so they pass this unchanged; the "context menu" group below builds
/// its own with just the flags it needs.
const _noActions = MessageActions(
  canEdit: false,
  onEdit: _noop,
  canDelete: false,
  onDelete: _noop,
  canManagePins: false,
  pinned: false,
  onTogglePin: _noop,
  canReport: false,
  onReport: _noop,
  canBlockAuthor: false,
  onBlockAuthor: _noop,
);

// The leading avatar is provider-backed now (it resolves the author's own
// avatar), so every row needs a ProviderScope even when a test cares about
// nothing avatar-related; the default, unauthenticated apiProvider fails
// fast on that lookup and the row falls back to initials, same as a real
// signed-out state would.
Widget _harness(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('an ungrouped row shows the avatar and the author name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        MessageRow(
          message: _message(),
          grouped: false,
          showNewDivider: false,
          knownUsernames: const {},
          onRetry: () {},
          onDiscard: () {},
          onPickReaction: (_) {},
          onReactionTap: (_) {},
          onVote: (_) {},
          actions: _noActions,
          editing: false,
          onSubmitEdit: (_) {},
          onCancelEdit: () {},
        ),
      ),
    );

    expect(find.byType(AppAvatar), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
  });

  testWidgets('a grouped continuation drops the avatar and the name, and keeps '
      'the timestamp in the gutter instead', (tester) async {
    await tester.pumpWidget(
      _harness(
        MessageRow(
          message: _message(),
          grouped: true,
          showNewDivider: false,
          knownUsernames: const {},
          onRetry: () {},
          onDiscard: () {},
          onPickReaction: (_) {},
          onReactionTap: (_) {},
          onVote: (_) {},
          actions: _noActions,
          editing: false,
          onSubmitEdit: (_) {},
          onCancelEdit: () {},
        ),
      ),
    );

    expect(find.byType(AppAvatar), findsNothing);
    expect(find.text('Priya'), findsNothing);
    // The gutter still carries a time, formatted the same way the header
    // line's own timestamp is.
    expect(find.text(formatMessageTime(1700000000000)), findsOneWidget);
  });

  testWidgets('the "New" divider only appears when asked for', (tester) async {
    await tester.pumpWidget(
      _harness(
        MessageRow(
          message: _message(),
          grouped: false,
          showNewDivider: true,
          knownUsernames: const {},
          onRetry: () {},
          onDiscard: () {},
          onPickReaction: (_) {},
          onReactionTap: (_) {},
          onVote: (_) {},
          actions: _noActions,
          editing: false,
          onSubmitEdit: (_) {},
          onCancelEdit: () {},
        ),
      ),
    );
    expect(find.text('NEW'), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        MessageRow(
          message: _message(),
          grouped: false,
          showNewDivider: false,
          knownUsernames: const {},
          onRetry: () {},
          onDiscard: () {},
          onPickReaction: (_) {},
          onReactionTap: (_) {},
          onVote: (_) {},
          actions: _noActions,
          editing: false,
          onSubmitEdit: (_) {},
          onCancelEdit: () {},
        ),
      ),
    );
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets(
    'a webhook row shows a code-box leading glyph and the tag badge',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(authorDisplayName: 'CI Bot'),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (_) {},
            isWebhook: true,
            actions: _noActions,
            editing: false,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
          ),
        ),
      );

      expect(find.byType(AppAvatar), findsNothing);
      expect(find.byType(AppBadge), findsOneWidget);
      expect(find.text('CI Bot'), findsOneWidget);
    },
  );

  testWidgets('a failed send shows the retry and discard actions', (
    tester,
  ) async {
    var retried = false;
    var discarded = false;
    await tester.pumpWidget(
      _harness(
        MessageRow(
          message: _message(failed: true),
          grouped: false,
          showNewDivider: false,
          knownUsernames: const {},
          onRetry: () => retried = true,
          onDiscard: () => discarded = true,
          onPickReaction: (_) {},
          onReactionTap: (_) {},
          onVote: (_) {},
          actions: _noActions,
          editing: false,
          onSubmitEdit: (_) {},
          onCancelEdit: () {},
        ),
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Discard'));
    expect(retried, isTrue);
    expect(discarded, isTrue);
  });

  group('reactions', () {
    testWidgets('a chip shows the real count and reflects whether you reacted', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (_) {},
            actions: _noActions,
            editing: false,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
            reactions: const [
              // Escaped rather than literal: the hygiene gate forbids emoji
              // codepoints in client source, and these are user content standing in
              // for a reaction, not interface chrome.
              api.ReactionSummary(emoji: '\u{1F44D}', count: 3, reacted: true),
              api.ReactionSummary(emoji: '\u{1F389}', count: 1, reacted: false),
            ],
          ),
        ),
      );

      expect(find.text('\u{1F44D}'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('\u{1F389}'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('tapping an existing chip reports which reaction was tapped', (
      tester,
    ) async {
      api.ReactionSummary? tapped;
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (r) => tapped = r,
            onVote: (_) {},
            actions: _noActions,
            editing: false,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
            reactions: const [
              api.ReactionSummary(emoji: '\u{1F44D}', count: 3, reacted: true),
            ],
          ),
        ),
      );

      await tester.tap(find.text('\u{1F44D}'));
      expect(tapped?.emoji, '\u{1F44D}');
      expect(tapped?.reacted, isTrue);
    });
  });

  group('polls', () {
    api.Poll poll({int? votedOption, bool closed = false}) => api.Poll(
      question: 'Best editor?',
      options: const [
        api.PollOption(position: 0, label: 'Vim', votes: 2),
        api.PollOption(position: 1, label: 'Emacs', votes: 1),
      ],
      totalVotes: 3,
      votedOption: votedOption,
      closeAt: null,
      closed: closed,
    );

    testWidgets('renders the question and every option', (tester) async {
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (_) {},
            actions: _noActions,
            editing: false,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
            poll: poll(),
          ),
        ),
      );

      expect(find.text('Best editor?'), findsOneWidget);
      expect(find.text('Vim'), findsOneWidget);
      expect(find.text('Emacs'), findsOneWidget);
      expect(find.text('3 votes'), findsOneWidget);
    });

    testWidgets('tapping an option casts a vote for its position', (
      tester,
    ) async {
      int? voted;
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (option) => voted = option,
            actions: _noActions,
            editing: false,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
            poll: poll(),
          ),
        ),
      );

      await tester.tap(find.text('Emacs'));
      expect(voted, 1);
    });

    testWidgets('a closed poll does not accept a tap', (tester) async {
      int? voted;
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (option) => voted = option,
            actions: _noActions,
            editing: false,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
            poll: poll(closed: true),
          ),
        ),
      );

      await tester.tap(find.text('Vim'));
      expect(voted, isNull);
      expect(find.text('3 votes - closed'), findsOneWidget);
    });
  });

  testWidgets('attachments render through the provider-backed view', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        MessageRow(
          message: _message(),
          grouped: false,
          showNewDivider: false,
          knownUsernames: const {},
          onRetry: () {},
          onDiscard: () {},
          onPickReaction: (_) {},
          onReactionTap: (_) {},
          onVote: (_) {},
          actions: _noActions,
          editing: false,
          onSubmitEdit: (_) {},
          onCancelEdit: () {},
          attachments: const [
            api.Attachment(
              id: 'a1',
              filename: 'notes.txt',
              contentType: 'text/plain',
              size: 2048,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  /// The picker is revealed on hover and opens a floating panel, so reaching the
  /// panel takes the pointer off the row that reveals the button. Six earlier
  /// tests pumped the panel directly and all passed while the feature could not
  /// be used with a mouse at all, so this drives the real pointer path.
  testWidgets('the emoji panel survives the pointer leaving the message row', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _harness(
        MessageRow(
          message: _message(),
          grouped: false,
          showNewDivider: false,
          knownUsernames: const {},
          onRetry: () {},
          onDiscard: () {},
          onPickReaction: (e) => picked = e,
          onReactionTap: (_) {},
          onVote: (_) {},
          actions: _noActions,
          editing: false,
          onSubmitEdit: (_) {},
          onCancelEdit: () {},
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    await mouse.moveTo(tester.getCenter(find.byType(MessageRow)));
    await tester.pumpAndSettle();

    final button = find.byType(EmojiPickerButton);
    expect(button, findsOneWidget, reason: 'hover should reveal the picker');

    await tester.tap(button);
    await tester.pumpAndSettle();
    final panel = find.byType(EmojiPickerPanel);
    expect(panel, findsOneWidget, reason: 'tapping should open the panel');

    // The failure this exists for: the panel occludes the row, so the pointer
    // leaves the MouseRegion and the button used to unmount, taking the panel
    // with it before any tile could be clicked.
    await mouse.moveTo(tester.getCenter(panel));
    await tester.pumpAndSettle();
    expect(
      panel,
      findsOneWidget,
      reason: 'the panel must outlive the pointer leaving the row',
    );

    final tile = find.byType(InkWell).hitTestable();
    if (tile.evaluate().isNotEmpty) {
      await tester.tap(tile.first);
      await tester.pumpAndSettle();
      expect(
        picked,
        isNotNull,
        reason: 'a tile click should report a reaction',
      );
    }
  });

  group('context menu', () {
    Widget rowWith(MessageActions actions) => _harness(
      MessageRow(
        message: _message(),
        grouped: false,
        showNewDivider: false,
        knownUsernames: const {},
        onRetry: () {},
        onDiscard: () {},
        onPickReaction: (_) {},
        onReactionTap: (_) {},
        onVote: (_) {},
        actions: actions,
        editing: false,
        onSubmitEdit: (_) {},
        onCancelEdit: () {},
      ),
    );

    // A press over the row's message text does not open the menu in this
    // bare harness (a Scaffold(body: MessageRow(...)) with no bounding
    // ListView around it, unlike every real call site): something between
    // the text and this widget's ancestor recognizers swallows it there.
    // Pressing near the region's own top-left corner, over the leading
    // avatar rather than the text, reliably reaches the menu instead.
    Offset pressPoint(WidgetTester tester) =>
        tester.getTopLeft(find.byType(MessageContextMenuRegion)) +
        const Offset(30, 30);

    testWidgets('long-press offers only what the caller allowed, plus copy', (
      tester,
    ) async {
      await tester.pumpWidget(rowWith(_noActions));

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

    testWidgets('a right-click opens the same menu edit allows', (
      tester,
    ) async {
      var edited = false;
      await tester.pumpWidget(
        rowWith(
          MessageActions(
            canEdit: true,
            onEdit: () => edited = true,
            canDelete: false,
            onDelete: _noop,
            canManagePins: false,
            pinned: false,
            onTogglePin: _noop,
            canReport: false,
            onReport: _noop,
            canBlockAuthor: false,
            onBlockAuthor: _noop,
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

    testWidgets('the pin item reads "Unpin" once already pinned', (
      tester,
    ) async {
      await tester.pumpWidget(
        rowWith(
          const MessageActions(
            canEdit: false,
            onEdit: _noop,
            canDelete: false,
            onDelete: _noop,
            canManagePins: true,
            pinned: true,
            onTogglePin: _noop,
            canReport: false,
            onReport: _noop,
            canBlockAuthor: false,
            onBlockAuthor: _noop,
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
            canEdit: false,
            onEdit: _noop,
            canDelete: true,
            onDelete: () => deleted = true,
            canManagePins: false,
            pinned: false,
            onTogglePin: _noop,
            canReport: false,
            onReport: _noop,
            canBlockAuthor: false,
            onBlockAuthor: _noop,
          ),
        ),
      );

      await tester.longPressAt(pressPoint(tester));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));

      expect(deleted, isTrue);
    });

    // The bug this covers: SlimmApi.report had no call site anywhere in
    // packages/app despite the endpoint, the wire model, and a full admin
    // triage screen all existing. Nothing gated that regressing, so this
    // fails without a rendered "Report message" item for someone else's
    // message the caller is allowed to report.
    testWidgets(
      'a message not authored by the caller offers Report and Block',
      (tester) async {
        var reported = false;
        var blocked = false;
        await tester.pumpWidget(
          rowWith(
            MessageActions(
              canEdit: false,
              onEdit: _noop,
              canDelete: false,
              onDelete: _noop,
              canManagePins: false,
              pinned: false,
              onTogglePin: _noop,
              canReport: true,
              onReport: () => reported = true,
              canBlockAuthor: true,
              onBlockAuthor: () => blocked = true,
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
      },
    );
  });

  group('inline edit', () {
    testWidgets('editing swaps the body for a pre-filled field', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (_) {},
            actions: _noActions,
            editing: true,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
          ),
        ),
      );

      expect(find.byType(MessageEditField), findsOneWidget);
      expect(find.widgetWithText(TextField, 'hello there'), findsOneWidget);
    });

    testWidgets('saving reports the edited text', (tester) async {
      String? submitted;
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (_) {},
            actions: _noActions,
            editing: true,
            onSubmitEdit: (text) => submitted = text,
            onCancelEdit: () {},
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'edited content');
      await tester.tap(find.text('Save'));

      expect(submitted, 'edited content');
    });

    testWidgets('cancel leaves the row rendered as unedited', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(
        _harness(
          MessageRow(
            message: _message(),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (_) {},
            actions: _noActions,
            editing: true,
            onSubmitEdit: (_) {},
            onCancelEdit: () => cancelled = true,
          ),
        ),
      );

      await tester.tap(find.text('Cancel'));
      expect(cancelled, isTrue);
    });
  });
}
