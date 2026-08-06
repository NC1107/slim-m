// SPDX-License-Identifier: Apache-2.0
/// Wiring `CanvasPane` -> `CanvasPresenceLayer`: a bubble shows only for the
/// channel this device has actually joined a call in, and never for a
/// blocked author, matching the filter every other canvas surface applies.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/blocks_controller.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_layer.dart';
import 'package:slimm_app/src/screens/canvas/canvas_self_presence_overlay.dart';
import 'package:slimm_rtc/rtc.dart';

import 'canvas_pane_harness.dart';
import 'voice_controller_harness.dart';

class _NoFetchBlocks extends BlocksController {
  _NoFetchBlocks(super.ref, BlocksState fixed) {
    state = fixed;
  }

  /// A real fetch racing this test's pumps could resolve after the fixed
  /// state above and quietly replace it, so this state never asks at all.
  @override
  Future<void> refresh() async {}
}

const _here = VoiceParticipant(
  identity: 'user-priya',
  name: 'Priya',
  isSpeaking: false,
  isMuted: false,
  isLocal: false,
  isScreenSharing: false,
);

const _blockedParticipant = VoiceParticipant(
  identity: 'user-blocked',
  name: 'Blocked Author',
  isSpeaking: false,
  isMuted: false,
  isLocal: false,
  isScreenSharing: false,
);

const _local = VoiceParticipant(
  identity: 'me',
  name: 'Me',
  isSpeaking: false,
  isMuted: false,
  isLocal: true,
  isScreenSharing: false,
);

void main() {
  testWidgets(
    'a participant in this channel\'s call renders a presence bubble',
    (tester) async {
      final fixture = CanvasPaneFixture();
      final container = fixture.container(
        extraOverrides: [
          voiceControllerProvider.overrideWith(
            (ref) => FixedVoiceController(
              ref,
              const VoiceState(channelId: 'c1', participants: [_here]),
            ),
          ),
          blocksProvider.overrideWith(
            (ref) => _NoFetchBlocks(ref, const BlocksState()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await pumpCanvasPane(tester, container);

      expect(find.byType(CanvasPresenceBubble), findsOneWidget);
    },
  );

  testWidgets(
    'the caller\'s own entry renders through the self overlay, never through '
    'the world-space layer meant for everyone else',
    (tester) async {
      final fixture = CanvasPaneFixture();
      final container = fixture.container(
        extraOverrides: [
          voiceControllerProvider.overrideWith(
            (ref) => FixedVoiceController(
              ref,
              const VoiceState(channelId: 'c1', participants: [_local, _here]),
            ),
          ),
          blocksProvider.overrideWith(
            (ref) => _NoFetchBlocks(ref, const BlocksState()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await pumpCanvasPane(tester, container);

      // One bubble each: the caller's own through the self overlay, Priya's through the world-space layer.
      expect(find.byType(CanvasPresenceBubble), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(CanvasSelfPresenceOverlay),
          matching: find.byType(CanvasPresenceBubble),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(CanvasPresenceLayer),
          matching: find.byType(CanvasPresenceBubble),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a call in some other channel shows no bubble on this one\'s canvas',
    (tester) async {
      final fixture = CanvasPaneFixture();
      final container = fixture.container(
        extraOverrides: [
          voiceControllerProvider.overrideWith(
            (ref) => FixedVoiceController(
              ref,
              const VoiceState(
                channelId: 'a-different-channel',
                participants: [_here],
              ),
            ),
          ),
          blocksProvider.overrideWith(
            (ref) => _NoFetchBlocks(ref, const BlocksState()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await pumpCanvasPane(tester, container);

      expect(find.byType(CanvasPresenceBubble), findsNothing);
    },
  );

  testWidgets('a blocked participant never renders a presence bubble', (
    tester,
  ) async {
    final fixture = CanvasPaneFixture();
    final container = fixture.container(
      extraOverrides: [
        voiceControllerProvider.overrideWith(
          (ref) => FixedVoiceController(
            ref,
            const VoiceState(
              channelId: 'c1',
              participants: [_here, _blockedParticipant],
            ),
          ),
        ),
        blocksProvider.overrideWith(
          (ref) =>
              _NoFetchBlocks(ref, const BlocksState(ids: {'user-blocked'})),
        ),
      ],
    );
    addTearDown(container.dispose);

    await pumpCanvasPane(tester, container);

    // Blocking filters one author; it is not a reason to hide the layer.
    expect(find.byType(CanvasPresenceBubble), findsOneWidget);
  });
}
