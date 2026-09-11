// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The scene contract: how slim turns a module's opaque output string into
/// something it can paint, without slim or the module knowing anything about
/// each other's internals.
///
/// A module returns a plain string (module ABI v1 has no content type). When
/// that string parses as a JSON object tagged `"$slim": "scene/1"`, slim reads
/// it as a scene and paints it (see `module_scene_painter.dart`) instead of
/// showing the raw text; anything else stays plain text exactly as before. So
/// this is a client-side reading of an ordinary string, not a wire change: a
/// module opts in simply by choosing to emit one.
///
/// Colours are named, not baked: an op may name a theme token (`accent`,
/// `surface`, `sunken`, `muted`, `text`, `border`, `danger`) and the painter
/// resolves it against the viewer's theme, so a module's drawing looks native
/// in light and dark alike without the module knowing which is in force. A
/// literal `#rrggbb` still passes through untouched.
library;

import 'dart:convert';

/// One drawing primitive. Coordinates are in the scene's own logical units
/// ([ModuleScene.width] by [ModuleScene.height]); the painter scales them to
/// whatever box it is given.
sealed class SceneOp {
  const SceneOp();
}

/// A colour grid: [data] is one character per cell, row-major, each a palette
/// index (`'0'`..). The workhorse behind boards, heatmaps and automata. A
/// non-null [tap] makes a tapped cell report `"$tap:row,col"`.
class CellsOp extends SceneOp {
  const CellsOp({
    required this.cols,
    required this.rows,
    required this.data,
    required this.palette,
    this.gap = 0,
    this.tap,
    this.tapBatch = false,
  });

  final int cols;
  final int rows;
  final String data;
  final List<String> palette;
  final double gap;
  final String? tap;

  /// Whether this module reads several cells from one [tap] action, as a
  /// `;`-separated list.
  ///
  /// A module call is a round trip and only one runs at a time, so a drag
  /// across a grid costs a call per cell without this. Defaults false because
  /// an older module would answer "bad cell" to a list, so a client may only
  /// send one to a module that has said it can read one. Additive both ways:
  /// a module that declares it still accepts a list of one, which is what a
  /// client that never looks at this field keeps sending.
  final bool tapBatch;
}

class RectOp extends SceneOp {
  const RectOp({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.radius = 0,
    this.tap,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final String? fill;
  final String? stroke;
  final double strokeWidth;
  final double radius;
  final String? tap;
}

class CircleOp extends SceneOp {
  const CircleOp({
    required this.cx,
    required this.cy,
    required this.r,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.tap,
  });

  final double cx;
  final double cy;
  final double r;
  final String? fill;
  final String? stroke;
  final double strokeWidth;
  final String? tap;
}

class LineOp extends SceneOp {
  const LineOp({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.stroke,
    this.strokeWidth = 1,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String? stroke;
  final double strokeWidth;
}

class TextOp extends SceneOp {
  const TextOp({
    required this.x,
    required this.y,
    required this.text,
    this.fill,
    this.size = 12,
    this.align = 'left',
  });

  final double x;
  final double y;
  final String text;
  final String? fill;
  final double size;
  final String align;
}

/// A whole scene: a logical canvas, the ops to draw on it, the opaque [state]
/// the module wants handed back on the next call, the [controls] to offer, a
/// one-line [status] caption, and whether the scene can still change ([live]).
class ModuleScene {
  const ModuleScene({
    required this.width,
    required this.height,
    required this.ops,
    this.background,
    this.state,
    this.controls = const [],
    this.status,
    this.live = false,
  });

  final double width;
  final double height;
  final List<SceneOp> ops;
  final String? background;
  final String? state;
  final List<String> controls;
  final String? status;
  final bool live;
}

/// Reads [raw] as a scene, or returns null if it is not one - the fast path
/// for the overwhelmingly common case of ordinary text output. Never throws:
/// malformed JSON, a wrong tag or a bad field all fall back to null (or a
/// skipped op) so a broken scene degrades to plain text rather than an error.
ModuleScene? parseModuleScene(String raw) {
  final trimmed = raw.trimLeft();
  if (!trimmed.startsWith('{')) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded[r'$slim'] != 'scene/1') return null;

  final opsRaw = decoded['ops'];
  final ops = <SceneOp>[];
  if (opsRaw is List) {
    for (final entry in opsRaw) {
      if (entry is Map) {
        final op = _parseOp(entry);
        if (op != null) ops.add(op);
      }
    }
  }

  return ModuleScene(
    width: _double(decoded['width'], 100),
    height: _double(decoded['height'], 100),
    ops: ops,
    background: _string(decoded['background']),
    state: _string(decoded['state']),
    controls: _stringList(decoded['controls']),
    status: _string(decoded['status']),
    live: decoded['live'] == true,
  );
}

SceneOp? _parseOp(Map<Object?, Object?> op) {
  switch (op['op']) {
    case 'cells':
      final data = _string(op['data']);
      if (data == null) return null;
      return CellsOp(
        cols: _double(op['cols'], 0).toInt(),
        rows: _double(op['rows'], 0).toInt(),
        data: data,
        palette: _stringList(op['palette']),
        gap: _double(op['gap'], 0),
        tap: _string(op['tap']),
        tapBatch: op['tap_batch'] == true,
      );
    case 'rect':
      return RectOp(
        x: _double(op['x'], 0),
        y: _double(op['y'], 0),
        w: _double(op['w'], 0),
        h: _double(op['h'], 0),
        fill: _string(op['fill']),
        stroke: _string(op['stroke']),
        strokeWidth: _double(op['sw'], 1),
        radius: _double(op['r'], 0),
        tap: _string(op['tap']),
      );
    case 'circle':
      return CircleOp(
        cx: _double(op['cx'], 0),
        cy: _double(op['cy'], 0),
        r: _double(op['r'], 0),
        fill: _string(op['fill']),
        stroke: _string(op['stroke']),
        strokeWidth: _double(op['sw'], 1),
        tap: _string(op['tap']),
      );
    case 'line':
      return LineOp(
        x1: _double(op['x1'], 0),
        y1: _double(op['y1'], 0),
        x2: _double(op['x2'], 0),
        y2: _double(op['y2'], 0),
        stroke: _string(op['stroke']),
        strokeWidth: _double(op['sw'], 1),
      );
    case 'text':
      final text = _string(op['s']);
      if (text == null) return null;
      return TextOp(
        x: _double(op['x'], 0),
        y: _double(op['y'], 0),
        text: text,
        fill: _string(op['fill']),
        size: _double(op['size'], 12),
        align: _string(op['align']) ?? 'left',
      );
    default:
      return null;
  }
}

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

String? _string(Object? value) => value is String ? value : null;

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];
