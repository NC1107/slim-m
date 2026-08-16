// SPDX-License-Identifier: Apache-2.0
/// Selecting several messages, and the two rules that are easy to get wrong.
///
/// The cap is one: a selection that has reached 64 must still let go of a
/// message, or picking one too many strands the user with no way back except
/// abandoning the whole selection. The other is that selection mode outlives
/// an empty selection, so deselecting the last message does not close the bar
/// mid-decision.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/message_selection.dart';

MessageSelectionController controller() => MessageSelectionController();

void main() {
  test('nothing is selected, and the mode is off, to begin with', () {
    final c = controller();
    expect(c.state.active, isFalse);
    expect(c.state.count, 0);
  });

  test('starting selects the message it started from', () {
    final c = controller()..start('m1');
    expect(c.state.active, isTrue);
    expect(c.state.contains('m1'), isTrue);
    expect(c.state.count, 1);
  });

  test('toggling adds, and toggling again removes', () {
    final c = controller()..start('m1');
    c.toggle('m2');
    expect(c.state.count, 2);
    c.toggle('m2');
    expect(c.state.contains('m2'), isFalse);
    expect(c.state.count, 1);
  });

  test('toggling does nothing at all while the mode is off', () {
    final c = controller()..toggle('m1');
    expect(
      c.state.active,
      isFalse,
      reason: 'an ordinary tap on a message must not silently begin selecting',
    );
    expect(c.state.count, 0);
  });

  test('cancelling ends the mode and forgets the selection', () {
    final c = controller()..start('m1');
    c.toggle('m2');
    c.clear();
    expect(c.state.active, isFalse);
    expect(c.state.count, 0);
  });

  test('deselecting the last message leaves the mode running', () {
    final c = controller()..start('m1');
    c.toggle('m1');
    expect(c.state.count, 0);
    expect(
      c.state.active,
      isTrue,
      reason:
          'the bar stays open to be cancelled deliberately, rather than '
          'vanishing under somebody who is still choosing',
    );
  });

  group('the cap', () {
    MessageSelectionController full() {
      final c = controller()..start('m0');
      for (var i = 1; i < maxBulkDeleteIds; i++) {
        c.toggle('m$i');
      }
      return c;
    }

    test('fills to exactly the server cap', () {
      final c = full();
      expect(c.state.count, maxBulkDeleteIds);
      expect(c.state.atCap, isTrue);
    });

    test('refuses one more rather than sending a request that would 400', () {
      final c = full();
      c.toggle('one-too-many');
      expect(c.state.count, maxBulkDeleteIds);
      expect(c.state.contains('one-too-many'), isFalse);
    });

    /// The rule the cap is most likely to break.
    test('still lets go of a message while full', () {
      final c = full();
      c.toggle('m0');
      expect(
        c.state.contains('m0'),
        isFalse,
        reason: 'a full selection that cannot be undone strands the user',
      );
      expect(c.state.atCap, isFalse);
      c.toggle('room-now');
      expect(
        c.state.contains('room-now'),
        isTrue,
        reason: 'and letting go must genuinely make room again',
      );
    });
  });

  test('the previous state is not mutated behind the caller', () {
    final c = controller()..start('m1');
    final before = c.state;
    c.toggle('m2');
    expect(
      before.count,
      1,
      reason: 'a widget holding the old value must not see it change under it',
    );
  });
}
