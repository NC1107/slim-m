// SPDX-License-Identifier: Apache-2.0
/// The infinite Voice Canvas, isolated so its complexity is contained.
///
/// Phase 5 spike surface only: a spatial index and the off-Riverpod hot path
/// that feeds the paint layer. No rendering, persistence, or wire protocol.
library;

export 'src/canvas_scene.dart';
export 'src/spatial_grid.dart';
