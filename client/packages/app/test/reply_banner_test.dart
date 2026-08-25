// SPDX-License-Identifier: Apache-2.0
/// The staged-reply strip above the composer: it names who a reply targets and
/// a one-line snippet, and cancels back to an ordinary send. A text-less parent
/// is named by what it carried instead, so replying to a photo is not a blank
/// "Replying to". Under SLIMM_UI_SNAPSHOTS it also writes a picture of the two
/// cases so the shape is looked at, not only asserted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/message_extras.dart';
import 'package:slimm_app/src/widgets/reply_banner.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row_harness.dart';
import 'ui_snapshot_support.dart';

/// Seeds [messageExtrasProvider] with what a parent carried, the way a live
/// frame or a REST page would, without a socket: the controller reads the
/// event stream at build, so an empty one keeps it inert.
List<Override> _carrying(
  String messageId,
  List<api.Attachment> attachments,
) => [
  liveEventsProvider.overrideWithValue(const Stream<api.ServerEvent>.empty()),
  messageExtrasProvider.overrideWith((ref) {
    final controller = MessageExtrasController(ref);
    controller.applyMessage(
      api.Message(
        id: messageId,
        channelId: 'c',
        authorId: 'bob',
        authorDisplayName: 'Bob',
        seq: 1,
        content: '',
        createdAt: 0,
        editedAt: null,
        attachments: attachments,
      ),
    );
    return controller;
  }),
];

const _photo = api.Attachment(
  id: 'a1',
  filename: 'sunset.png',
  contentType: 'image/png',
  size: 2048,
);

void main() {
  testWidgets('names the reply target and cancels', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 460,
          child: ReplyBanner(
            message: message(
              id: 'p',
              authorId: 'ada',
              authorDisplayName: 'Ada Lovelace',
              content: 'the original message being replied to',
            ),
            onCancel: () => cancelled++,
          ),
        ),
      ),
    );

    expect(find.textContaining('Replying to Ada Lovelace'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel reply'));
    expect(cancelled, 1);
  });

  testWidgets('names a text-less parent by what it carried', (tester) async {
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 460,
          child: ReplyBanner(
            message: message(
              id: 'p',
              authorId: 'bob',
              authorDisplayName: 'Bob',
              content: '',
            ),
            onCancel: () {},
          ),
        ),
        overrides: _carrying('p', const [_photo]),
      ),
    );

    expect(find.textContaining('Photo'), findsOneWidget);
  });

  testWidgets('renders a picture of both cases', (tester) async {
    tester.view.physicalSize = const Size(500, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) {
            final tokens = Theme.of(context).extension<AppTokens>()!;
            return ColoredBox(
              color: tokens.surfaceBase,
              child: RepaintBoundary(
                key: snapshotBoundary,
                child: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReplyBanner(
                        message: message(
                          id: 'p1',
                          authorId: 'ada',
                          authorDisplayName: 'Ada Lovelace',
                          content: 'the original message being replied to',
                        ),
                        onCancel: () {},
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      ReplyBanner(
                        message: message(
                          id: 'p2',
                          authorId: 'bob',
                          authorDisplayName: 'Bob',
                          content: '',
                        ),
                        onCancel: () {},
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        overrides: _carrying('p2', const [_photo]),
      ),
    );
    await tester.pump();
    await writeSnapshot(tester, 'reply-banner');
  });
}
