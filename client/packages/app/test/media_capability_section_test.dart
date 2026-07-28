// SPDX-License-Identifier: Apache-2.0
/// Tests for the device capability check: nothing runs until asked, a
/// successful probe shows each capability's real answer, and a probe that
/// cannot finish reads as "could not tell" rather than a false "unsupported".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/diagnostics/debug_log.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/media_capability_section.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

class _FakeProbe implements MediaDevicesProbe {
  _FakeProbe({this.micTracks, this.screenSources});

  final int? micTracks;
  final int? screenSources;

  @override
  Future<int> countMicrophoneTracks() async => micTracks!;

  @override
  Future<int> countScreenSources() async => screenSources!;
}

/// Never resolves the way [MediaCapabilities.probeAll] promises to: it throws
/// outright, the shape the UI must treat as "could not tell" rather than
/// quietly reporting both capabilities as missing.
class _ThrowingCapabilities extends MediaCapabilities {
  const _ThrowingCapabilities();

  @override
  Future<Map<String, CapabilityResult>> probeAll() async {
    throw StateError('capability probe exploded');
  }
}

/// Lets a test hold the microphone half of the probe open, so the in-flight
/// state can be observed before it resolves.
class _DelayedProbe implements MediaDevicesProbe {
  final micCompleter = Completer<int>();

  @override
  Future<int> countMicrophoneTracks() => micCompleter.future;

  @override
  Future<int> countScreenSources() async => 1;
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      home: const Scaffold(body: MediaCapabilitySection()),
    ),
  );
}

void main() {
  testWidgets('nothing is claimed until the button is pressed', (tester) async {
    final container = ProviderContainer(
      overrides: [
        mediaCapabilitiesProvider.overrideWithValue(
          MediaCapabilities(probe: _FakeProbe(micTracks: 0, screenSources: 0)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Check this device'), findsOneWidget);
    expect(find.text('Microphone'), findsNothing);
    expect(find.text('Screen capture'), findsNothing);
    expect(find.textContaining('Could not tell'), findsNothing);
  });

  testWidgets("a successful check shows each capability's real answer", (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        mediaCapabilitiesProvider.overrideWithValue(
          MediaCapabilities(probe: _FakeProbe(micTracks: 2, screenSources: 0)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.tap(find.text('Check this device'));
    await tester.pumpAndSettle();

    expect(find.text('Microphone'), findsOneWidget);
    expect(find.textContaining('Available: 2 audio track'), findsOneWidget);
    expect(find.text('Screen capture'), findsOneWidget);
    expect(
      find.textContaining(
        'Not available: the portal offered no capturable sources',
      ),
      findsOneWidget,
    );
    expect(find.text('Check again'), findsOneWidget);

    final entries = container.read(debugLogProvider);
    expect(entries, isNotEmpty);
    expect(entries.first.source, 'capabilities');
    expect(entries.first.level, DiagnosticSeverity.info);
  });

  testWidgets('a probe that throws renders as unknown, not unsupported', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        mediaCapabilitiesProvider.overrideWithValue(
          const _ThrowingCapabilities(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.tap(find.text('Check this device'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not tell what this device supports'),
      findsOneWidget,
    );
    expect(find.text('Microphone'), findsNothing);
    expect(find.textContaining('Not available'), findsNothing);

    final entries = container.read(debugLogProvider);
    expect(entries, isNotEmpty);
    expect(entries.first.source, 'capabilities');
    expect(entries.first.level, DiagnosticSeverity.warning);
  });

  testWidgets('an in-flight check disables the button until it resolves', (
    tester,
  ) async {
    final probe = _DelayedProbe();
    final container = ProviderContainer(
      overrides: [
        mediaCapabilitiesProvider.overrideWithValue(
          MediaCapabilities(probe: probe),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.tap(find.text('Check this device'));
    await tester.pump();

    expect(find.text('Checking...'), findsOneWidget);
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.onPressed, isNull);

    probe.micCompleter.complete(1);
    await tester.pumpAndSettle();

    expect(find.text('Check again'), findsOneWidget);
  });
}
