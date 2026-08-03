// SPDX-License-Identifier: Apache-2.0
/// Pins the property that lets reactions, pins and polls skip reconciliation.
///
/// `CLAUDE.md`'s "Reconciling an edit nobody was online for" names an open
/// debt: an offline client never learns about a reaction, a pin or a poll
/// vote it missed. That is correct today only because none of the three is
/// persisted locally - every REST fetch that returns a message (send, list,
/// sync, search) already carries all of them in full, so a fresh render is
/// always a fresh read rather than a stale cache. `MessageExtras`
/// (`packages/app/lib/src/providers/message_extras.dart`) and
/// `PinsController` (`packages/app/lib/src/providers/pins_controller.dart`)
/// both say so in their own doc comments and both hold their state in plain
/// Riverpod memory, never in this database.
///
/// The day one of them gains a drift table, that reasoning stops applying
/// and the debt reopens - with none of `message_ops`' machinery reusable,
/// since a reaction op is per-viewer (never broadcast with reactor ids) and
/// a pin op is not idempotent by message id the way an edit or delete is.
/// This test is the tripwire: it fails the moment a new table appears here,
/// so whoever adds one is pointed at the debt note before shipping a cache
/// nothing keeps in sync.
///
/// `channel_categories` (docs/decisions/0006-channel-categories.md) is
/// listed here deliberately rather than reopening that debt: it is replaced
/// wholesale on every channel refresh
/// (`MessageStore.replaceCategories`, called from `ChannelRefresher.refresh`),
/// the same shape `channels` itself already has, never reconciled
/// incrementally the way a reaction, pin or poll vote would need to be. A
/// missed live event only means the next full channel refresh - already
/// triggered by any category change - is what catches it up, not a gap
/// nothing revisits.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_data/data.dart';

void main() {
  test('the local schema holds only channels, messages and categories',
      () async {
    final db = SlimmDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final names = db.allTables.map((t) => t.actualTableName).toSet();
    expect(
      names,
      {'channels', 'messages', 'channel_categories'},
      reason: 'a new local table beyond these three means reactions, pins or '
          'polls (or something else) just started being cached - read the '
          'reconciliation debt in CLAUDE.md before adding one, and build '
          'reconciliation for it in the same change rather than leaving '
          'this test to catch it later',
    );
  });
}
