// SPDX-License-Identifier: Apache-2.0
/// Fails a captured surface whose settle budget was not actually enough:
/// see CLAUDE.md's "The report card overflow, and how far the mid-flight
/// capture problem actually spreads" for the bug this exists to catch.
///
/// `ui_snapshot_support.dart`'s own settle budget (two or three fixed
/// pumps) is a guess about how long a surface's async work takes, not a
/// proof that it is finished. The report card overflow shipped invisible
/// because a card's own `initState` fires a *second*, nested resolve that
/// needed one more turn of the event loop than that budget gave it, and
/// until it landed the row showed the short, harmless placeholder
/// `'Loading...'` rather than the real, overflowing name - so every prior
/// capture of that screen was quietly checking a not-yet-loaded state.
///
/// [expectSettled] does not trust the settle budget either: it reads every
/// visible string right where the budget says "done", pumps a further
/// [extraSettlePumps] bare frames (no [Duration], so nothing here can hang
/// the way `pumpAndSettle` does on a perpetual spinner - a bare pump only
/// flushes already-completed microtasks and paints one more frame, it does
/// not wait for a running ticker to finish), and reads the same strings
/// again. A real, finished product state cannot change what it says just
/// because the event loop got one more turn; a placeholder still waiting on
/// its own async hop can.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bare frames pumped past the declared settle budget before deciding a
/// surface is actually done. Each one only flushes microtasks already
/// completed by the time it runs, so this is headroom for a resolve chained
/// a couple of hops deep (the report card's own shape), not a wait.
const extraSettlePumps = 3;

/// Every string a person reading the screen would see, in tree order:
/// [Text.data], or [Text.textSpan]'s own plain-text rendering for a rich
/// span (mentions, inline code, and the markdown-rendered message body all
/// go through [Text.rich]).
List<String> renderedText(WidgetTester tester) {
  final strings = <String>[];
  for (final element in tester.elementList(find.byType(Text))) {
    final text = element.widget as Text;
    final data = text.data;
    if (data != null) {
      strings.add(data);
    } else if (text.textSpan != null) {
      strings.add(text.textSpan!.toPlainText());
    }
  }
  return strings;
}

/// Reads [tester]'s visible text, pumps [extraSettlePumps] further bare
/// frames, and fails if that changed anything - unless [knownTransient],
/// the escape hatch for a real, benign transition between two valid loading
/// states (see `ui_snapshot_test.dart`'s own `thread` entry and CLAUDE.md's
/// "how far the mid-flight-capture problem actually spreads" for the one
/// case this is true of today).
///
/// Call this where a caller has decided a surface is settled and is about
/// to treat what is on screen as the real thing - before a snapshot is
/// written, before an overflow assertion is trusted - never afterward, or
/// the extra pumps this runs would let the very drift it looks for slip in
/// ahead of the read.
Future<void> expectSettled(
  WidgetTester tester,
  String snapshotName, {
  bool knownTransient = false,
}) async {
  final before = renderedText(tester);
  for (var i = 0; i < extraSettlePumps; i++) {
    await tester.pump();
  }
  final after = renderedText(tester);
  if (knownTransient || _sameText(before, after)) return;
  fail(
    'mid-flight capture: "$snapshotName" still had content resolving when '
    'the settle budget declared it done.\n'
    'captured: $before\n'
    'settled:  $after',
  );
}

bool _sameText(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
