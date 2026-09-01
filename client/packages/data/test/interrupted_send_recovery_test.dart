// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A send interrupted by the process ending is the one state in the send
/// lifecycle with no way out, and this is what gives it one.
///
/// `addPending` writes the row, then the send either lands and is replaced by
/// the server's copy or catches an `ApiException` and is marked failed. A
/// crash, a force-quit, or the OS reclaiming a backgrounded app runs neither
/// branch, and the row stays pending for good.
///
/// Nothing rescued it. The reconnect retry reads `failedMessages`, which
/// selects `failed`; the row's own Retry button is offered for `failed`. So it
/// read as sending forever, was never retried, and could not be retried by
/// hand. Both halves are asserted below - the sweep is only worth anything if
/// the row it produces is one the existing recovery paths can see.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_data/data.dart';

void main() {
  late SlimmDatabase db;
  late MessageStore store;

  setUp(() {
    db = SlimmDatabase(NativeDatabase.memory());
    store = MessageStore(db);
  });

  tearDown(() => db.close());

  Future<void> pending(String id) => store.addPending(
        id: id,
        channelId: 'chan-1',
        authorId: 'user-1',
        content: 'interrupted',
      );

  test('a pending row is invisible to both recovery paths until swept',
      () async {
    await pending('local-1');

    expect(
      await store.failedMessages(),
      isEmpty,
      reason: 'this is the bug: the reconnect retry cannot see it',
    );
    final before = (await store.watchChannel('chan-1').first).single;
    expect(before.pending, isTrue);
    expect(
      before.failed,
      isFalse,
      reason: 'and the row offers no Retry button either',
    );
  });

  test('the sweep turns it into a failure both paths can act on', () async {
    await pending('local-1');

    expect(await failInterruptedSends(store), 1);

    final row = (await store.watchChannel('chan-1').first).single;
    expect(row.pending, isFalse);
    expect(row.failed, isTrue);
    expect(row.failureReason, interruptedSendReason);
    expect(
      (await store.failedMessages()).map((m) => m.id),
      ['local-1'],
      reason: 'the reconnect retry picks it up now',
    );
  });

  test('it keeps what was typed rather than dropping the row', () async {
    await pending('local-1');
    await failInterruptedSends(store);

    final row = (await store.watchChannel('chan-1').first).single;
    expect(row.content, 'interrupted');
  });

  test('a send that already failed is left with its own reason', () async {
    await pending('local-1');
    await store.markFailed('local-1', reason: 'the server refused it');

    expect(
      await failInterruptedSends(store),
      0,
      reason: 'markFailed clears pending, so the sweep must not see it',
    );
    final row = (await store.watchChannel('chan-1').first).single;
    expect(
      row.failureReason,
      'the server refused it',
      reason: 'overwriting it would lose why it actually failed',
    );
  });

  test('sweeping with nothing pending changes nothing', () async {
    expect(await failInterruptedSends(store), 0);
  });
}
