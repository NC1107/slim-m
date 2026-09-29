// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A bot's private answer: it appears marked as private, is dismissible, and
/// stays in its own channel.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/ephemeral_messages.dart';
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/widgets/ephemeral_tray.dart';
import 'package:slimm_design_system/design_system.dart';

api.MessageEphemeral _frame(String id, String channel, String text) =>
    api.MessageEphemeral(
      channelId: channel,
      message: api.EphemeralMessage(
        id: id,
        channelId: channel,
        authorId: 'bot',
        authorDisplayName: 'Helper',
        content: text,
        inReplyToId: 'm1',
        createdAt: 1,
      ),
    );

Future<(ProviderContainer, StreamController<api.ServerEvent>)> _pump(
  WidgetTester tester,
  String channelId,
) async {
  final events = StreamController<api.ServerEvent>.broadcast();
  addTearDown(events.close);
  final container = ProviderContainer(
    overrides: [liveEventsProvider.overrideWithValue(events.stream)],
  );
  addTearDown(container.dispose);
  container.read(ephemeralMessagesProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: EphemeralTray(channelId: channelId)),
      ),
    ),
  );
  return (container, events);
}

void main() {
  testWidgets('a private answer renders as private and can be dismissed', (
    tester,
  ) async {
    final (_, events) = await _pump(tester, 'c1');
    expect(find.text('you have 500 chips'), findsNothing);

    events.add(_frame('e1', 'c1', 'you have 500 chips'));
    await tester.pumpAndSettle();

    expect(find.text('you have 500 chips'), findsOneWidget);
    expect(find.textContaining('Only you can see this'), findsOneWidget);
    expect(find.textContaining('Helper'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('you have 500 chips'), findsNothing);
  });

  testWidgets('another channel\'s private answer does not show here', (
    tester,
  ) async {
    final (_, events) = await _pump(tester, 'c1');
    events.add(_frame('e1', 'c2', 'elsewhere'));
    await tester.pumpAndSettle();
    expect(find.text('elsewhere'), findsNothing);
  });

  testWidgets('a redelivered id shows once and only the newest few stay', (
    tester,
  ) async {
    final (container, events) = await _pump(tester, 'c1');
    events
      ..add(_frame('e1', 'c1', 'first'))
      ..add(_frame('e1', 'c1', 'first'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    for (var i = 2; i <= maxEphemeralPerChannel + 2; i++) {
      events.add(_frame('e$i', 'c1', 'msg $i'));
    }
    await tester.pumpAndSettle();
    expect(
      container.read(channelEphemeralMessagesProvider('c1')).length,
      maxEphemeralPerChannel,
    );
    expect(find.text('first'), findsNothing);
    expect(find.text('msg ${maxEphemeralPerChannel + 2}'), findsOneWidget);
  });
}
