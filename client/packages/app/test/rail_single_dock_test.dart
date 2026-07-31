// SPDX-License-Identifier: Apache-2.0
/// The rail used to stack two docks when a call was live elsewhere: a call
/// bar (`VoiceStripIndicator`) directly above `RailUserFooter`, each with
/// its own mic and headset toggle. This is what fails if that regresses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/widgets/rail_call_summary.dart';
import 'package:slimm_app/src/widgets/voice_strip_indicator.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import 'ui_snapshot_support.dart';
import 'voice_controller_harness.dart';

class _FixedVoiceController extends VoiceController {
  _FixedVoiceController(super.ref, VoiceState fixed)
    : super(session: FakeSession()) {
    state = fixed;
  }
}

void main() {
  setUpAll(loadRealFonts);

  const inMainCall = VoiceState(
    channelId: 'c-main',
    state: VoiceSessionState.connected,
  );

  testWidgets(
    'a call live elsewhere renders one dock in the channel list, not two',
    (tester) async {
      final fixture = await fixtureContainer(
        extraOverrides: [
          voiceControllerProvider.overrideWith(
            (ref) => _FixedVoiceController(ref, inMainCall),
          ),
        ],
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.dark, AppTokens.dark),
            routerConfig: fixtureRouter('/channels'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.byType(VoiceStripIndicator),
        findsNothing,
        reason: 'the call bar must fold into the footer, not sit above it',
      );
      expect(find.byType(RailCallSummary), findsOneWidget);
      expect(
        find.bySemanticsLabel('Mute'),
        findsOneWidget,
        reason: 'one mic toggle, not one per dock',
      );
      expect(
        find.bySemanticsLabel('Deafen'),
        findsOneWidget,
        reason: 'one headset toggle, not one per dock',
      );
      expect(find.bySemanticsLabel('Leave call'), findsOneWidget);
      expect(find.bySemanticsLabel('Personal settings'), findsOneWidget);

      await teardownFixture(tester, fixture.container, fixture.db);
    },
  );
}
