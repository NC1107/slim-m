// SPDX-License-Identifier: Apache-2.0
/// The spatial index on its own, with no `dart:ui` in its import graph.
///
/// A separate entry point so the benchmark can AOT-compile and run outside
/// the Flutter engine, and so the boundary is enforced by resolution rather
/// than by intent.
library;

export 'src/spatial_grid.dart';
