// SPDX-License-Identifier: Apache-2.0
/// A right-click on an in-call participant tile used to do nothing; a tap
/// already opened their profile (the only route to per-participant volume
/// that does not go through the member pane), so right-click reaches the
/// same callback rather than a route of its own.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/call_participant_tiles.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

const _participant = VoiceParticipant(
  identity: 'user-priya',
  name: 'Priya',
  isSpeaking: false,
  isMuted: false,
  isLocal: false,
  isScreenSharing: false,
);

void main() {
  testWidgets('a right-click opens the profile, same as a tap', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: Scaffold(
            body: CallParticipantTile(
              participant: _participant,
              onTap: () => opened++,
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.byType(CallParticipantTile)),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('a null onTap leaves the tile inert to a right-click too', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const Scaffold(
            body: CallParticipantTile(participant: _participant),
          ),
        ),
      ),
    );

    // Not throwing is the assertion: no onTap must not mean a crash on right-click.
    await tester.tapAt(
      tester.getCenter(find.byType(CallParticipantTile)),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
  });
}
