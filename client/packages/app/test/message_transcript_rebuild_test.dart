// SPDX-License-Identifier: Apache-2.0
/// Measures whether starting an inline edit rebuilds message rows that are
/// not the one being edited.
///
/// `_editingId` used to be a plain field on `_ChannelScreenState`, so every
/// `setState` that changed it re-ran the whole `StreamBuilder<List<Message>>`
/// subtree, which reconstructs every visible `MessageRow` (and re-parses its
/// markdown body) regardless of whether that row's own `editing` flag
/// actually flipped. `debugOnRebuildDirtyWidget` is the framework's own
/// per-element rebuild hook (used by the widget inspector), and it is used
/// here rather than any counter added to production code, so nothing under
/// test needed to change shape to be measurable.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/message_context_menu.dart';
import 'package:slimm_app/src/widgets/message_text.dart';

import 'channel_history_harness.dart';

/// How many times a widget of type [T] was rebuilt while [action] ran.
Future<int> _rebuildsOf<T extends Widget>(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  var count = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    if (element.widget.runtimeType == T) count++;
  };
  try {
    await action();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return count;
}

Future<void> _openMenuAndTap(
  WidgetTester tester,
  String messageId,
  String label,
) async {
  final region = find.descendant(
    of: find.byKey(ValueKey(messageId)),
    matching: find.byType(MessageContextMenuRegion),
  );
  final node = tester.getSemantics(region);
  tester.binding.performSemanticsAction(
    SemanticsActionEvent(
      type: SemanticsAction.longPress,
      nodeId: node.id,
      viewId: tester.view.viewId,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'editing one message does not rebuild every other message body',
    (tester) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);

      await mountChannel(
        tester,
        serverSeqs: [for (var i = 1; i <= 8; i++) i],
        seededSeqs: [for (var i = 1; i <= 8; i++) i],
        messageAuthorId: 'bob',
      );

      final rebuilds = await _rebuildsOf<MessageBody>(
        tester,
        () => _openMenuAndTap(tester, 'm4', 'Edit'),
      );

      expect(
        rebuilds,
        0,
        reason:
            'starting an edit on one message must not re-parse the markdown '
            'of every other visible row; only the edited row swaps its body '
            'for the edit field',
      );
    },
  );
}
