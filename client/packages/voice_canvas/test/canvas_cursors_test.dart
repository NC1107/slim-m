// SPDX-License-Identifier: Apache-2.0
/// [CanvasCursors]: upsert, prune-by-age, and the id-keyed removal a block
/// needs.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

void main() {
  test('upsert records a cursor and notifies once', () {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);
    var notifications = 0;
    cursors.addListener(() => notifications++);

    cursors.upsert(id: 'alice', x: 1, y: 2, label: 'Alice', colorIndex: 0);

    expect(cursors.all.map((c) => c.id), ['alice']);
    expect(cursors.all.single.x, 1);
    expect(cursors.all.single.y, 2);
    expect(notifications, 1);
  });

  test('a later upsert for the same id replaces it rather than adding one', () {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);

    cursors.upsert(id: 'alice', x: 1, y: 2, label: 'Alice', colorIndex: 0);
    cursors.upsert(id: 'alice', x: 5, y: 9, label: 'Alice', colorIndex: 0);

    expect(cursors.all.length, 1);
    expect(cursors.all.single.x, 5);
    expect(cursors.all.single.y, 9);
  });

  test('pruneOlderThan drops only cursors stale past the ttl', () {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);
    final base = DateTime(2026, 1, 1);

    cursors.upsert(
      id: 'stale',
      x: 0,
      y: 0,
      label: 'Stale',
      colorIndex: 0,
      now: base,
    );
    cursors.upsert(
      id: 'fresh',
      x: 0,
      y: 0,
      label: 'Fresh',
      colorIndex: 1,
      now: base.add(const Duration(seconds: 5)),
    );

    cursors.pruneOlderThan(
      const Duration(seconds: 6),
      now: base.add(const Duration(seconds: 8)),
    );

    expect(cursors.all.map((c) => c.id), ['fresh']);
  });

  test('pruneOlderThan is a no-op, and notifies nothing, when nothing is stale',
      () {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);
    final base = DateTime(2026, 1, 1);
    cursors.upsert(
        id: 'alice', x: 0, y: 0, label: 'Alice', colorIndex: 0, now: base);

    var notifications = 0;
    cursors.addListener(() => notifications++);
    cursors.pruneOlderThan(
      const Duration(seconds: 10),
      now: base.add(const Duration(seconds: 1)),
    );

    expect(cursors.all.length, 1);
    expect(notifications, 0);
  });

  test('remove drops one cursor by id and is a silent no-op for an unknown one',
      () {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);
    cursors.upsert(id: 'alice', x: 0, y: 0, label: 'Alice', colorIndex: 0);

    var notifications = 0;
    cursors.addListener(() => notifications++);
    cursors.remove('nobody');
    expect(notifications, 0, reason: 'removing an unknown id must not notify');

    cursors.remove('alice');
    expect(cursors.all, isEmpty);
    expect(notifications, 1);
  });

  test('clear drops every cursor at once', () {
    final cursors = CanvasCursors();
    addTearDown(cursors.dispose);
    cursors.upsert(id: 'alice', x: 0, y: 0, label: 'Alice', colorIndex: 0);
    cursors.upsert(id: 'bob', x: 1, y: 1, label: 'Bob', colorIndex: 1);

    cursors.clear();

    expect(cursors.all, isEmpty);
  });
}
