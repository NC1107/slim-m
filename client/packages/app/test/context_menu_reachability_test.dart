// SPDX-License-Identifier: Apache-2.0
/// The context menus stay reachable by long press, including to a screen
/// reader.
///
/// Both regions open on a right-click or a long press. An earlier note in this
/// repository claimed that left them with no semantic action either, so report,
/// block, edit, delete and pin were unreachable to assistive technology. That
/// was wrong, and it was wrong in the direction that matters: `GestureDetector`
/// publishes `SemanticsAction.longPress` for its own `onLongPress`, so VoiceOver
/// and TalkBack have always been able to open these.
///
/// It is worth a test anyway, because that reachability is a side effect of one
/// widget choice rather than anything stated. Swapping `GestureDetector` for a
/// `Listener`, or setting `excludeFromSemantics`, removes it silently, and the
/// only symptom is that a group of people quietly lose every message action.
///
/// What is genuinely still missing is the keyboard: these rows do not take
/// focus and no key opens the menu, so a keyboard-only user has no route.
/// That is recorded in CLAUDE.md rather than fixed here.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/context_menu_region.dart';
import 'package:slimm_design_system/design_system.dart';

const Key _anchor = Key('anchor');

Future<SemanticsHandle> _pump(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: Center(
          child: ContextMenuRegion(
            itemsBuilder: (close) => [
              AppMenuItem(label: 'Report', onTap: close),
              AppMenuItem(label: 'Block', onTap: close),
            ],
            child: const SizedBox(
              key: _anchor,
              width: 120,
              height: 40,
              child: Text('a member row'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return handle;
}

void main() {
  testWidgets('the region publishes a long-press action', (tester) async {
    final handle = await _pump(tester);

    final node = tester.getSemantics(find.byKey(_anchor));
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
      reason: 'without this every action in the menu is lost to a screen '
          'reader, and nothing else would say so',
    );
    handle.dispose();
  });

  testWidgets('invoking that action really opens the menu', (tester) async {
    final handle = await _pump(tester);

    expect(find.text('Report'), findsNothing);
    final node = tester.getSemantics(find.byKey(_anchor));
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.longPress,
    );
    await tester.pumpAndSettle();

    // Publishing the action and honouring it are two different things, and a
    // published action nothing answers is worse than none.
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
    handle.dispose();
  });
}
