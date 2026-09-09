// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Everything painted on an overlay must also exist in its semantics tree.
///
/// The e2e harness went red for two days (#1126) on a button that was on
/// screen, enabled and clickable with a mouse, yet absent from the semantics
/// tree: a dialog route had swallowed it into its own label and dropped its
/// tap action. A screen reader user hit the same wall. Nothing in the suite
/// looked at the tree, so nothing noticed. This does, for every registered
/// overlay in both shipped shapes: each visible text has a node that is not
/// the route scope itself, and each enabled button has a node that taps.
///
/// A failure names the overlay and the widget. Fix the widget, never the
/// test: a control that only a mouse can reach is a bug, whatever the reason.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

import 'support/overlay_registry.dart';
import 'ui_snapshot_support.dart';

/// One unreachable widget: what it is and why the tree lost it.
String _problem(String kind, String label, String why) =>
    '$kind "$label": $why';

/// Every node in the live semantics tree, hidden (off-screen) ones included:
/// what a screen reader can walk to, independent of which render object a
/// node happens to hang off.
List<SemanticsNode> _allNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  // Any node will do as a starting point; the root is however far up it goes.
  var root = tester.getSemantics(find.byType(MaterialApp));
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return nodes;
}

/// The nodes whose label or tooltip carries [text], on its own or merged
/// with siblings. A `Tooltip` announces through the tooltip slot, not the
/// label, and that is how `IconButton(tooltip:)` names itself.
Iterable<SemanticsNode> _naming(List<SemanticsNode> nodes, String text) =>
    nodes.where((n) => n.label.contains(text) || n.tooltip.contains(text));

/// Whether [element] sits under a deliberate exclusion: an `ExcludeSemantics`
/// or a `Semantics(excludeSemantics: true)` ancestor, the way a button hides
/// its visual label behind its semantic one, or an avatar hides its initials
/// behind the person's name. Those texts are meant to be absent.
bool _excluded(Element element) {
  var excluded = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is ExcludeSemantics && widget.excluding) excluded = true;
    if (widget is Semantics && widget.excludeSemantics) excluded = true;
    return !excluded;
  });
  return excluded;
}

List<String> _audit(WidgetTester tester) {
  final problems = <String>[];
  final nodes = _allNodes(tester);

  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    // A Text announcing something other than what it shows (a counter's
    // "0/2000" reads as "2000 characters remaining") is judged by that.
    final text = (widget.semanticsLabel ?? widget.data)?.trim();
    if (text == null || text.isEmpty || text == overlayOpenerLabel) continue;
    if (_excluded(element)) continue;
    final naming = _naming(nodes, text).toList();
    if (naming.isEmpty) {
      problems.add(_problem('text', text, 'appears in no semantics node'));
    } else if (naming.every(
      (n) => n.getSemanticsData().flagsCollection.scopesRoute,
    )) {
      problems.add(
        _problem('text', text, 'was merged into the route node itself'),
      );
    }
  }

  void checkButton(String kind, String label) {
    final naming = _naming(nodes, label);
    if (naming.isEmpty) {
      problems.add(_problem(kind, label, 'appears in no semantics node'));
    } else if (!naming.any(
      (n) => n.getSemanticsData().hasAction(SemanticsAction.tap),
    )) {
      problems.add(_problem(kind, label, 'has a node, but none of them taps'));
    }
  }

  for (final element in find.byType(AppButton).evaluate()) {
    final button = element.widget as AppButton;
    if (button.disabled || button.onPressed == null) continue;
    checkButton('AppButton', button.semanticLabel ?? button.label);
  }
  for (final element in find.byType(AppIconButton).evaluate()) {
    final button = element.widget as AppIconButton;
    if (button.onPressed == null) continue;
    checkButton('AppIconButton', button.semanticLabel);
  }
  for (final element in find.byType(IconButton).evaluate()) {
    final button = element.widget as IconButton;
    if (button.onPressed == null || button.tooltip == null) continue;
    checkButton('IconButton', button.tooltip!);
  }
  return problems;
}

void main() {
  setUpAll(loadRealFonts);

  for (final viewport in overlayViewports.entries) {
    for (final overlay in overlays.entries) {
      testWidgets(
        '${overlay.key} at ${viewport.key} is fully reachable by semantics',
        (tester) async {
          tester.view.physicalSize = viewport.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final handle = tester.ensureSemantics();

          final fixture = await fixtureContainer();
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: fixture.container,
              child: MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(Brightness.dark, AppTokens.dark),
                routerConfig: overlayRouter(overlay.value),
              ),
            ),
          );
          await tester.pump();
          await tester.tap(find.text(overlayOpenerLabel));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump(const Duration(milliseconds: 350));

          final problems = _audit(tester);
          expect(
            problems,
            isEmpty,
            reason:
                '${overlay.key} at ${viewport.key} paints widgets a screen '
                'reader cannot reach:\n  ${problems.join('\n  ')}',
          );
          expect(tester.takeException(), isNull);

          handle.dispose();
          await teardownFixture(tester, fixture.container, fixture.db);
        },
      );
    }
  }
}
