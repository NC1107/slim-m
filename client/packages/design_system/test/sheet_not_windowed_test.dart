// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// With Flutter's `windowing` flag on (the Linux build enables it for the
/// pop-out), a bare `showDialog` pushes a native OS window and ignores the
/// route builder. Every sheet, select and time picker must stay a
/// [DialogRoute] inside the main window.
library;

// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart' as features;
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

Future<_Routes> _pump(WidgetTester tester, Widget Function(BuildContext) open) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final observer = _Routes();
  return tester
      .pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark, AppTokens.dark),
          navigatorObservers: [observer],
          home: Scaffold(body: Builder(builder: (c) => Center(child: open(c)))),
        ),
      )
      .then((_) => observer);
}

void main() {
  late bool windowing;

  setUp(() {
    windowing = features.isWindowingEnabled;
    features.isWindowingEnabled = true;
  });
  tearDown(() => features.isWindowingEnabled = windowing);

  testWidgets('showAppSheet at desktop width pushes an in-window DialogRoute',
      (tester) async {
    // Only the Linux build enables windowing, so only it takes the in-window route.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final observer = await _pump(
      tester,
      (context) => TextButton(
        onPressed: () => showAppSheet<void>(
          context,
          builder: (_) => const Text('sheet body'),
        ),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(observer.pushed.last, isA<DialogRoute<void>>());
    expect(find.text('sheet body'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('showAppTimePicker pushes an in-window DialogRoute',
      (tester) async {
    // Only the Linux build enables windowing, so only it takes the in-window route.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final observer = await _pump(
      tester,
      (context) => TextButton(
        onPressed: () => showAppTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 9, minute: 30),
        ),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(observer.pushed.last, isA<DialogRoute<TimeOfDay>>());
    expect(find.byType(TimePickerDialog), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
