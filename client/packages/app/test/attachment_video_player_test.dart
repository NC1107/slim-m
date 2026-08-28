// SPDX-License-Identifier: Apache-2.0
/// [AttachmentVideoPlayer] constructs a real `media_kit` [Player] the moment
/// it mounts (see the widget's own field initializer), so every test here
/// needs [MediaKit.ensureInitialized] and a real libmpv on the machine
/// running it - `client-ci.yml`'s test job installs `libmpv-dev` for exactly
/// this. What is tested never needs that player to actually open anything:
/// a caller with no access token fails inside `AttachmentVideoSource.open`
/// itself, before `Player.open` is ever reached, so this is deterministic
/// rather than dependent on a real network fetch settling in time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/attachment_video_player.dart';
import 'package:slimm_design_system/design_system.dart';

const _video = api.Attachment(
  id: 'v1',
  filename: 'clip.mp4',
  contentType: 'video/mp4',
  size: 12000000,
);

void main() {
  setUpAll(MediaKit.ensureInitialized);

  testWidgets('signed out surfaces the load failure through AppErrorState', (
    tester,
  ) async {
    final signedOut = api.SlimmApi(baseUrl: Uri.parse('http://localhost:1'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(signedOut)],
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const Scaffold(body: AttachmentVideoPlayer(attachment: _video)),
        ),
      ),
    );
    await tester.pump();

    // Still loading here (the failure lands on the next pump).
    expect(
      find.byWidgetPredicate(
        (w) => w is CircularProgressIndicator && w.value == null,
      ),
      findsNothing,
    );
    expect(find.text('Loading video…'), findsOneWidget);

    await tester.pump();

    expect(
      find.text(
        'Could not load ${_video.filename}: you are signed out. '
        'Sign in and try again.',
      ),
      findsOneWidget,
    );
    expect(find.byType(Video), findsNothing);
  });
}
