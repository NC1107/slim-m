// SPDX-License-Identifier: Apache-2.0
/// Pure geometry shared between [CanvasPresenceLayer] (the interactive
/// shell every tile's controls live on) and [CanvasPresenceBackdrop] (the
/// non-interactive paint of a tile sent to the back) - both need the exact
/// same rects, on the same viewport, or a control could drift from the
/// pixels it is meant to be manipulating. See `canvas_presence_layer.dart`'s
/// own doc for why depth needs two widgets at all.
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

typedef CameraViewBuilder = Widget Function(String identity);
typedef ScreenShareViewBuilder = Widget Function(String identity);

const presenceCameraOnSize = Size(220, 160);
const presenceCameraOffSize = Size(140, 140);
const presenceScreenShareSize = Size(360, 203);

/// Every tile key this call's roster has right now: one camera per
/// participant, plus a screen tile for whoever is sharing.
Set<String> presenceTileKeys(List<VoiceParticipant> participants) {
  final keys = <String>{};
  for (final p in participants) {
    keys.add('camera:${p.identity}');
    if (p.isScreenSharing) keys.add('screen:${p.identity}');
  }
  return keys;
}

/// `'screen'` or `'camera'` - the same two strings the server's own
/// `CanvasMediaSlot.kind` uses, so a key can be sent straight through with
/// no translation.
String presenceTileKind(String key) =>
    key.startsWith('screen:') ? 'screen' : 'camera';

/// The participant a tile key names, stripped of its `kind:` prefix.
String presenceTileIdentity(String key) => key.substring(key.indexOf(':') + 1);

Size presenceTileSize(String key, Map<String, VoiceParticipant> byIdentity) {
  if (key.startsWith('screen:')) return presenceScreenShareSize;
  final participant = byIdentity[key.substring('camera:'.length)];
  return (participant?.isCameraOn ?? false)
      ? presenceCameraOnSize
      : presenceCameraOffSize;
}

/// Every tile's current world rect - an override's own drag or resize if it
/// has one, [layout]'s default arrangement otherwise - excluding whatever is
/// hidden this call. The one place both widgets read a rect from, so a
/// control can never end up manipulating a different box than the one a
/// person sees painted.
Map<String, Rect> presenceOnCanvasRects({
  required Set<String> keys,
  required CanvasPresenceLayout layout,
  required CanvasPresenceTileOverrides overrides,
  required Map<String, VoiceParticipant> byIdentity,
  required bool hideSelfCamera,
}) {
  final defaults = layout.arrange(
    keys,
    sizeFor: (key) => presenceTileSize(key, byIdentity),
  );
  final onCanvas = <String, Rect>{};
  for (final key in keys) {
    final state = overrides.stateFor(key);
    if (state.hidden) continue;
    if (hideSelfCamera &&
        key.startsWith('camera:') &&
        byIdentity[key.substring('camera:'.length)]?.isLocal == true) {
      continue;
    }
    onCanvas[key] = state.rect ?? defaults[key]!;
  }
  return onCanvas;
}

/// [keys] sorted so a tile this viewer has ever dragged or resized paints
/// above every untouched one, most recently touched last (topmost) - the
/// same "a real sheet of paper does not slide under the pile" rule
/// regardless of which paint layer (front or backdrop) is asking.
List<String> presencePaintOrder(Set<String> keys, int? Function(String) zFor) {
  final ordered = keys.toList(growable: false);
  final rank = <String, int>{
    for (var i = 0; i < ordered.length; i++) ordered[i]: i,
  };
  final withZ = ordered.map((key) => (key: key, z: zFor(key) ?? -1)).toList();
  withZ.sort((a, b) {
    final byZ = a.z.compareTo(b.z);
    return byZ != 0 ? byZ : rank[a.key]!.compareTo(rank[b.key]!);
  });
  return [for (final entry in withZ) entry.key];
}

/// A world rect converted to screen space under [camera] - the one place
/// that arithmetic lives, so a tile's controls and its (possibly
/// backdrop-painted) content can never round differently.
Rect presenceScreenRect(Rect worldRect, Camera camera) => Rect.fromLTWH(
  (worldRect.left - camera.x) * camera.zoom,
  (worldRect.top - camera.y) * camera.zoom,
  worldRect.width * camera.zoom,
  worldRect.height * camera.zoom,
);
