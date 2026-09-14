// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Report 2 in the backlog channel, in the owner's own words: "after
/// choosing a screen share screen there is never an option to choose a
/// different one while in the same call, clicking screenshare always goes
/// back to whatever was just chosen" - a bare tap on the share button while
/// already sharing only ever stopped it, with no route back to the picker
/// short of ending the share and hoping to notice a second, separate tap
/// would start a fresh one.
///
/// A long press (or a right-click) is the route this file proves: it stops
/// the running share and reopens the picker, with the source just used
/// highlighted rather than silently reused, while an ordinary tap keeps
/// stopping outright - `scripts/lib/e2e_voice.py` already drives that same
/// tap by its "Stop sharing" tooltip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/providers/voice_flags.dart';
import 'package:slimm_app/src/screens/voice_call_controls.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_call_controls_harness.dart';

const _sources = [
  ScreenShareSource(id: '1', name: 'Screen 1'),
  ScreenShareSource(id: '2', name: 'Screen 2'),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a bare tap on an active share still stops it outright, unchanged',
    (tester) async {
      final session = InertSession(
        needsSource: true,
        sources: Future.value(_sources),
      );
      await pumpControls(
        tester,
        const VoiceFlags(
          state: VoiceSessionState.connected,
          screenSharing: true,
        ),
        session: session,
      );

      await tester.tap(find.byTooltip('Stop sharing'));
      await tester.pumpAndSettle();

      expect(session.screenShareCalls, hasLength(1));
      expect(session.screenShareCalls.single.enabled, isFalse);
    },
  );

  testWidgets(
    'a long press on an active share stops it, then reopens the picker to '
    'choose a different source',
    (tester) async {
      final session = InertSession(
        needsSource: true,
        sources: Future.value(_sources),
      );
      await pumpControls(
        tester,
        const VoiceFlags(
          state: VoiceSessionState.connected,
          screenSharing: true,
        ),
        session: session,
      );

      await tester.longPress(find.byTooltip('Stop sharing'));
      await tester.pumpAndSettle();

      expect(
        find.text('Everyone in the call will see it until you stop sharing.'),
        findsOneWidget,
        reason: 'the picker must reopen, not silently reuse the old source',
      );

      await tester.tap(find.text('Screen 2'));
      await tester.pumpAndSettle();

      expect(
        session.screenShareCalls.map((c) => (c.enabled, c.sourceId)),
        [(false, null), (true, '2')],
        reason:
            'the running share stops before the new source starts, rather '
            'than trusting a hot swap',
      );
    },
  );

  testWidgets('the picker highlights the source already in effect, rather than '
      'reopening with no memory of it at all', (tester) async {
    final session = InertSession(
      needsSource: true,
      sources: Future.value(_sources),
    );
    final container = await pumpControls(
      tester,
      const VoiceFlags(state: VoiceSessionState.connected),
      session: session,
    );

    // First share: picks Screen 1.
    await tester.tap(find.byTooltip('Share a screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Screen 1'));
    await tester.pumpAndSettle();
    expect(session.screenShareCalls.last.sourceId, '1');

    // Rebuilt over the same container, so `_CallControlsState` survives with its remembered source, exactly as it does across a real `VoiceFlags` update.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: Scaffold(
            body: CallControls(
              controller: container.read(voiceControllerProvider.notifier),
              voice: const VoiceFlags(
                state: VoiceSessionState.connected,
                screenSharing: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.longPress(find.byTooltip('Stop sharing'));
    await tester.pumpAndSettle();

    final rows = tester
        .widgetList<AppListRow>(find.byType(AppListRow))
        .toList();
    final highlighted = rows.where((r) => r.selected).toList();
    expect(highlighted, hasLength(1));
    expect(highlighted.single.label, 'Screen 1');
  });

  testWidgets(
    'on Linux the long press still switches, going straight to the other '
    'source with no second dialog',
    (tester) async {
      final session = InertSession(
        needsSource: true,
        sources: Future.value(_sources),
        sourcePickerUseful: false,
      );
      await pumpControls(
        tester,
        const VoiceFlags(
          state: VoiceSessionState.connected,
          screenSharing: true,
        ),
        session: session,
      );

      await tester.longPress(find.byTooltip('Stop sharing'));
      await tester.pumpAndSettle();

      expect(
        find.text('Everyone in the call will see it until you stop sharing.'),
        findsNothing,
      );
      expect(session.screenShareCalls.map((c) => (c.enabled, c.sourceId)), [
        (false, null),
        (true, '1'),
      ]);
    },
  );

  testWidgets(
    'a long press does nothing on a platform with no source to switch '
    'between at all',
    (tester) async {
      final session = InertSession();
      await pumpControls(
        tester,
        const VoiceFlags(
          state: VoiceSessionState.connected,
          screenSharing: true,
        ),
        session: session,
      );

      await tester.longPress(find.byTooltip('Stop sharing'));
      await tester.pumpAndSettle();

      expect(session.screenShareCalls, isEmpty);
    },
  );
}
