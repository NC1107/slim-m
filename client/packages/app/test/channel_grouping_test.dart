// SPDX-License-Identifier: Apache-2.0
/// Tests for the ordering shared between the rail's sections and the
/// next/previous-channel shortcuts.
///
/// The defect these pin: `orderedChannels` kept a DM group in raw listing
/// order, while `DirectMessagesSection` always rendered the personal space
/// first. Cycling and the rail agreed only when the personal space happened
/// to sort first already, so a channel opened for the first time after some
/// other DM cycled to a different channel than the one shown on screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/channel_grouping.dart';
import 'package:slimm_data/data.dart';

Channel _channel(
  String id, {
  String kind = 'text',
  bool isPersonalSpace = false,
}) => Channel(
  id: id,
  name: id,
  kind: kind,
  createdAt: 0,
  cursor: 0,
  lastReadSeq: 0,
  isPersonalSpace: isPersonalSpace,
);

void main() {
  group('splitPersonalSpace', () {
    test('pulls the flagged channel out regardless of its position', () {
      final dm1 = _channel('dm1', kind: 'dm');
      final personal = _channel('personal', kind: 'dm', isPersonalSpace: true);
      final dm2 = _channel('dm2', kind: 'dm');

      final split = splitPersonalSpace([dm1, personal, dm2]);

      expect(split.personal?.id, 'personal');
      expect(split.others.map((c) => c.id), ['dm1', 'dm2']);
    });

    test('answers no personal space when none is flagged', () {
      final split = splitPersonalSpace([_channel('dm1', kind: 'dm')]);
      expect(split.personal, isNull);
      expect(split.others.map((c) => c.id), ['dm1']);
    });
  });

  group('orderedChannels', () {
    test('groups direct messages, text, then voice', () {
      final ordered = orderedChannels([
        _channel('voice1', kind: 'voice'),
        _channel('text1'),
        _channel('dm1', kind: 'dm'),
      ]);

      expect(ordered.map((c) => c.id), ['dm1', 'text1', 'voice1']);
    });

    /// The bug: the personal space was opened after another DM, so it
    /// sorted second by `createdAt` - which `DirectMessagesSection` never
    /// does.
    test('the personal space cycles first, matching the rail, even when it '
        'was not the first DM opened', () {
      final dm = _channel('dm1', kind: 'dm');
      final personal = _channel('personal', kind: 'dm', isPersonalSpace: true);

      final ordered = orderedChannels([dm, personal]);

      expect(
        ordered.map((c) => c.id).first,
        'personal',
        reason:
            "DirectMessagesSection always renders the personal space "
            'above every other DM, whatever order they were opened in',
      );
    });
  });
}
