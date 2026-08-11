// SPDX-License-Identifier: Apache-2.0
/// `ChannelCategorySections` used to `ref.watch(voiceControllerProvider)` at
/// its own top level and hand the result down to every row it built, text
/// channels included. `voiceControllerProvider` updates on essentially every
/// room event (active speaker, mute, connection quality), so during a call
/// every text-channel row in the rail rebuilt on every one of those, when
/// before the categories merge only the voice section ever watched it.
///
/// A behavioural test would have to distinguish "rebuilt" from "rebuilt and
/// happened to render the same pixels", which nothing in `flutter_test`
/// exposes without instrumenting the widgets themselves. Reading the source
/// is what `route_reachability_test.dart` already does for the same shape of
/// reason: this is a scoping property of which widget owns a `ref.watch`,
/// not a rendered outcome a pixel-level assertion could see.
///
/// Both files are read through `support/code_only.dart` before either
/// `contains` check runs: the "must appear" half is the vulnerable one,
/// and reproduced directly - removing the real `ref.watch(...)` call and
/// leaving `// used to be ref.watch(voiceControllerProvider) before a
/// refactor` in its place still passed, since a bare substring search
/// cannot tell a comment's prose from real code.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/code_only.dart';

void main() {
  test(
    'ChannelCategorySections does not watch voiceControllerProvider itself',
    () {
      final lib = Directory('lib');
      expect(
        lib.existsSync(),
        isTrue,
        reason: 'run this from the app package root',
      );

      final source = codeOnly(
        File('lib/src/widgets/channel_rail_sections.dart').readAsStringSync(),
      );
      expect(
        source.contains('voiceControllerProvider'),
        isFalse,
        reason:
            'watching the voice controller here rebuilds every row in every '
            'category - text channels included - on every room event; only '
            'VoiceChannelRow itself should watch it',
      );
    },
  );

  test('VoiceChannelRow watches voiceControllerProvider itself', () {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'run this from the app package root',
    );

    final source = codeOnly(
      File('lib/src/widgets/channel_rail_channel_rows.dart').readAsStringSync(),
    );
    expect(
      source.contains('ref.watch(voiceControllerProvider)'),
      isTrue,
      reason:
          'the row itself must be the one thing that reacts to a room '
          'event, so a rebuild stays scoped to the voice rows on screen '
          'rather than the whole rail',
    );
  });
}
