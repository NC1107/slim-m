// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `presenceOnCanvasRects` is the one place both presence widgets read a tile's
/// world rect from, so a control never manipulates a different box than the one
/// painted. Three rules decide what it returns and none were tested: a hidden
/// tile is dropped, this viewer's own camera is dropped when hideSelfCamera is
/// set, and a tile the viewer has dragged uses its override rect over the
/// layout default.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_geometry.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

VoiceParticipant _p(String identity, {bool local = false}) => VoiceParticipant(
  identity: identity,
  name: identity,
  isSpeaking: false,
  isMuted: false,
  isLocal: local,
  isScreenSharing: false,
);

void main() {
  final layout = const CanvasPresenceLayout();

  test('a hidden tile is dropped, the rest keep their default rect', () {
    final me = _p('me');
    final them = _p('them');
    final keys = presenceTileKeys([me, them]);
    final byIdentity = {'me': me, 'them': them};
    final overrides = CanvasPresenceTileOverrides();
    final hidden = keys.firstWhere((k) => presenceTileIdentity(k) == 'me');
    overrides.setHidden(hidden, true);

    final rects = presenceOnCanvasRects(
      keys: keys,
      layout: layout,
      overrides: overrides,
      byIdentity: byIdentity,
      hideSelfCamera: false,
    );

    expect(rects.containsKey(hidden), isFalse);
    expect(rects, hasLength(1));
  });

  test('hideSelfCamera drops this viewer\'s own camera, not a remote one', () {
    final me = _p('me', local: true);
    final them = _p('them');
    final keys = presenceTileKeys([me, them]);
    final byIdentity = {'me': me, 'them': them};

    final shown = presenceOnCanvasRects(
      keys: keys,
      layout: layout,
      overrides: CanvasPresenceTileOverrides(),
      byIdentity: byIdentity,
      hideSelfCamera: true,
    );

    expect(shown.keys.map(presenceTileIdentity), ['them']);

    // Without the flag, the local camera is back.
    final all = presenceOnCanvasRects(
      keys: keys,
      layout: layout,
      overrides: CanvasPresenceTileOverrides(),
      byIdentity: byIdentity,
      hideSelfCamera: false,
    );
    expect(all, hasLength(2));
  });

  test('a dragged tile uses its override rect over the layout default', () {
    final them = _p('them');
    final keys = presenceTileKeys([them]);
    final byIdentity = {'them': them};
    final overrides = CanvasPresenceTileOverrides();
    final key = keys.single;
    overrides.setRect(key, const Rect.fromLTWH(500, 600, 220, 160));

    final rects = presenceOnCanvasRects(
      keys: keys,
      layout: layout,
      overrides: overrides,
      byIdentity: byIdentity,
      hideSelfCamera: false,
    );

    expect(rects[key], overrides.stateFor(key).rect);
  });
}
