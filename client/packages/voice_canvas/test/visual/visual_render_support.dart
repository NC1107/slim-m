// SPDX-License-Identifier: Apache-2.0
/// Rasterising a canvas scene straight to a PNG, with no widget mounted at
/// all: a plain `test()`, a `ui.PictureRecorder`, and a file write.
///
/// This is the technique a previous design pass used to get real pixels out
/// of these painters without going through `testWidgets` at all, since the
/// full canvas pane is known to hang a widget test on a loaded box. Nothing
/// here pumps a frame or touches `WidgetTester`.
///
/// **Every PNG this writes is rasterised in software** (`flutter test` has
/// no GPU), which can paint a thin diagonal stroke as broken or dotted at
/// a low effective pixel width even when the geometry is correct - see
/// `dpi_probe_test.dart`'s own finding on `zoom_stress_0.25x.png` before
/// reading that one as a real gap in the ink.
///
/// **The same rasteriser does not blur or alpha-blend a `BoxShadow` either**,
/// so a soft translucent shadow paints as flat opaque black with a hard edge
/// in every PNG written here and by the app package's own snapshot tests.
/// A sign-off pass took the floating dock's shadow for a real defect on that
/// evidence, then disproved it with a standalone probe and against a live
/// browser, where the same shadow blurs correctly. Check a shadow in a real
/// browser before believing a snapshot about one.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Set to write PNGs; unset, every scene still runs (so a regression in the
/// painters themselves still throws) but nothing is written to disk.
bool get writingVisuals => Platform.environment['SLIMM_CANVAS_VISUAL'] == '1';

const visualOutDir = 'build/canvas-visual';

/// The real IBM Plex faces, loaded by hand from the sibling design_system
/// package - by path, not by pub dependency, since this package deliberately
/// carries none. Without this every glyph in a rendered note or cursor label
/// draws as a filled box, which would make the very thing under review
/// unreadable rather than merely unstyled.
Future<void> loadVisualFonts() async {
  const design = '../design_system/fonts';
  await _loadFamily('IBM Plex Sans Visual', [
    '$design/IBMPlexSans-Regular.ttf',
    '$design/IBMPlexSans-Medium.ttf',
  ]);
}

Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
  }
  await loader.load();
}

/// The one family name every visual scene's text uses, once loaded.
const visualSansFamily = 'IBM Plex Sans Visual';

/// Paints [draw] onto a fresh `width`x`height` surface and writes it as
/// `$visualOutDir/$name.png`, unless [writingVisuals] is false.
///
/// Runs the paint callback regardless of [writingVisuals], so a painter
/// throwing (a real regression) still fails the test even when nobody asked
/// for the pixels.
Future<void> renderVisualScene(
  String name,
  int width,
  int height,
  void Function(Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas);
  final picture = recorder.endRecording();
  if (!writingVisuals) {
    picture.dispose();
    return;
  }
  final image = await picture.toImage(width, height);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  Directory(visualOutDir).createSync(recursive: true);
  File('$visualOutDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}
