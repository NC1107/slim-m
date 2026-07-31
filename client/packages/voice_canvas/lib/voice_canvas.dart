// SPDX-License-Identifier: Apache-2.0
/// The infinite Voice Canvas, isolated so its complexity is contained.
///
/// The spatial index and off-Riverpod hot path the Phase 5 spike proved, plus
/// the surface built on them: a document, three paint layers, and pointer
/// handling. Persistence and the wire protocol stay in the app layer, and
/// nothing under `lib/` may import Riverpod - `test/canvas_scene_test.dart`
/// enforces that, which is what keeps the render loop honest.
library;

export 'src/canvas_document.dart';
export 'src/canvas_hit_test.dart';
export 'src/canvas_painters.dart' show DraftStroke;
export 'src/canvas_scene.dart';
export 'src/canvas_surface.dart';
export 'src/spatial_grid.dart';
export 'src/stroke_splitter.dart';
