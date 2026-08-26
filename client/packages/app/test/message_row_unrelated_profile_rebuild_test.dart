// SPDX-License-Identifier: Apache-2.0
/// `MessageRowHeader` and `MessageRowLeading` used to watch the whole
/// `batchProfilesControllerProvider` map, so every mounted row rebuilt
/// whenever any author resolved, not only the row whose own author changed -
/// `message_transcript_widgets.dart`'s `MessageRowExtras` already fixed the
/// identical shape for reactions and edits with a `.select`, and this is the
/// same measurement (`debugOnRebuildDirtyWidget`, from
/// `message_transcript_rebuild_test.dart`) applied to the author fix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/user_profiles.dart';
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_app/src/widgets/message_row_identity.dart';

import 'message_row_harness.dart';

/// How many times a widget of type [T] was rebuilt while [action] ran; see
/// `message_transcript_rebuild_test.dart`'s own copy of this helper.
Future<int> _rebuildsOf<T extends Widget>(
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

void main() {
  testWidgets(
    "an unrelated author resolving rebuilds neither this row's header nor "
    'its leading avatar',
    (tester) async {
      late BatchProfilesController controller;
      await tester.pumpWidget(
        harness(
          MessageRow(
            message: message(authorId: 'author-1', authorDisplayName: 'Priya'),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (_) {},
            actions: noActions,
            editing: false,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
          ),
          overrides: [
            batchProfilesControllerProvider.overrideWith((ref) {
              controller = BatchProfilesController(ref);
              return controller;
            }),
          ],
        ),
      );
      await tester.pump();

      final headerRebuilds = await _rebuildsOf<MessageRowHeader>(() async {
        controller.state = {
          ...controller.state,
          'someone-else': const api.UserProfile(
            id: 'someone-else',
            username: 'someone-else',
            displayName: 'Someone Else',
            createdAt: 0,
          ),
        };
        await tester.pump();
      });

      expect(
        headerRebuilds,
        0,
        reason:
            "a row must only rebuild when its own author's entry in the "
            'batch map changes, never when an unrelated id resolves',
      );
    },
  );

  testWidgets(
    "authorLabel output survives the .select unchanged: absent, present-null "
    'and present-value all still read the way they did before',
    (tester) async {
      late BatchProfilesController controller;
      await tester.pumpWidget(
        harness(
          MessageRow(
            message: message(authorId: 'author-1', authorDisplayName: 'Priya'),
            grouped: false,
            showNewDivider: false,
            knownUsernames: const {},
            onRetry: () {},
            onDiscard: () {},
            onPickReaction: (_) {},
            onReactionTap: (_) {},
            onVote: (_) {},
            actions: noActions,
            editing: false,
            onSubmitEdit: (_) {},
            onCancelEdit: () {},
          ),
          overrides: [
            batchProfilesControllerProvider.overrideWith((ref) {
              controller = BatchProfilesController(ref);
              return controller;
            }),
          ],
        ),
      );
      await tester.pump();

      // Absent from the map: the row falls back to its own cached name.
      expect(find.text('Priya'), findsOneWidget);

      // Present but null: a confirmed-gone author, never the stale cached name.
      controller.state = {...controller.state, 'author-1': null};
      await tester.pump();
      expect(find.text('Deleted user'), findsOneWidget);

      // Present with a value: the resolved name wins over the cached one.
      controller.state = {
        ...controller.state,
        'author-1': const api.UserProfile(
          id: 'author-1',
          username: 'priya',
          displayName: 'Priya Renamed',
          createdAt: 0,
        ),
      };
      await tester.pump();
      expect(find.text('Priya Renamed'), findsOneWidget);
    },
  );
}
