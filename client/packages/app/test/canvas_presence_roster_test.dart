// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Who is here, drawn as a face-pile: real presence only, deduped across
/// the call roster and live cursors, and nothing shown at all when nobody
/// but this device can be proven present.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/avatar_bytes.dart';
import 'package:slimm_app/src/providers/user_profiles.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_roster.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

const _me = VoiceParticipant(
  identity: 'me',
  name: 'Me',
  isSpeaking: false,
  isMuted: false,
  isLocal: true,
  isScreenSharing: false,
);

VoiceParticipant _remote(String id, String name) => VoiceParticipant(
  identity: id,
  name: name,
  isSpeaking: false,
  isMuted: false,
  isLocal: false,
  isScreenSharing: false,
);

// AuthorAvatar reads userProfileProvider and avatarBytesProvider; both fixed to null so this test needs no real api/session chain.
Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    userProfileProvider.overrideWith((ref, id) async => null),
    avatarBytesProvider.overrideWith((ref, key) async => null),
  ],
  child: MaterialApp(
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: Scaffold(body: child),
  ),
);

void main() {
  // pumpAndSettle rather than a bare pump, so a live cursor update fully lands before each assertion.
  testWidgets('nobody present renders nothing at all', (tester) async {
    await tester.pumpWidget(
      _wrap(const CanvasPresenceRoster(callParticipants: [])),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppAvatar), findsNothing);
  });

  testWidgets("this device's own call participation never counts as "
      'presence', (tester) async {
    await tester.pumpWidget(
      _wrap(const CanvasPresenceRoster(callParticipants: [_me])),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppAvatar), findsNothing);
  });

  testWidgets('a remote call participant renders one avatar with a named '
      'semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(CanvasPresenceRoster(callParticipants: [_remote('u1', 'Ada')])),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppAvatar), findsOneWidget);
    expect(find.bySemanticsLabel('On this canvas: Ada'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a live cursor with no call renders one avatar too', (
    tester,
  ) async {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);
    cursors.upsert(id: 'u2', x: 0, y: 0, label: 'Priya', colorIndex: 0);

    await tester.pumpWidget(
      _wrap(CanvasPresenceRoster(callParticipants: const [], cursors: cursors)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppAvatar), findsOneWidget);
    expect(find.bySemanticsLabel('On this canvas: Priya'), findsOneWidget);
  });

  testWidgets('the same id present as both a call participant and a live '
      'cursor renders once, not twice', (tester) async {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);
    cursors.upsert(id: 'u1', x: 0, y: 0, label: 'Ada', colorIndex: 0);

    await tester.pumpWidget(
      _wrap(
        CanvasPresenceRoster(
          callParticipants: [_remote('u1', 'Ada')],
          cursors: cursors,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppAvatar), findsOneWidget);
  });

  testWidgets('past four present, the rest collapse into a +N chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CanvasPresenceRoster(
          callParticipants: [
            _remote('u1', 'Ada'),
            _remote('u2', 'Bob'),
            _remote('u3', 'Cy'),
            _remote('u4', 'Dee'),
            _remote('u5', 'Eve'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppAvatar), findsNWidgets(4));
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('a cursor arriving live, with no rebuild from the parent, '
      'still updates the roster', (tester) async {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);

    await tester.pumpWidget(
      _wrap(CanvasPresenceRoster(callParticipants: const [], cursors: cursors)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppAvatar), findsNothing);

    cursors.upsert(id: 'u1', x: 0, y: 0, label: 'Ada', colorIndex: 0);
    await tester.pumpAndSettle();

    expect(find.byType(AppAvatar), findsOneWidget);
  });
}
