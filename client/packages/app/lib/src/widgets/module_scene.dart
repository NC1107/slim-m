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

import 'module_scene_path.dart';

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

/// An arbitrary shape, from an SVG-style `d` string. The op that stops the
/// contract capping a drawing at rectangles and circles: anything a module can
/// describe with lines and beziers, it can now draw.
///
/// [steps] is already parsed and already bounded (see [sceneMaxPathSteps]), so
/// the painter walks a fixed list rather than a string.
class PathOp extends SceneOp {
  const PathOp({
    required this.steps,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.tap,
  });

  final List<ScenePathStep> steps;
  final String? fill;
  final String? stroke;
  final double strokeWidth;

  /// Hit-tested against the filled shape, so a tappable path wants a [fill];
  /// an unfilled outline has almost no interior to land in.
  final String? tap;
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

/// One note: a frequency to ring, when it starts relative to the scene's own
/// age in seconds, and how long it rings. The same three numbers
/// `assets/audio/synth.py`'s `Note` carries, minus `gain` - a module states
/// none, so it cannot ask for a louder note than the app's own chimes ever
/// play. See [NotesOp] for the ceilings already applied by the time one of
/// these exists.
class SceneNote {
  const SceneNote({
    required this.frequency,
    required this.start,
    required this.seconds,
  });

  final double frequency;
  final double start;
  final double seconds;
}

/// A module asks slim to play a short sound built from these notes, rather
/// than shipping a sample or waveform of its own. Slim renders them with the
/// same bell-like voice `assets/audio/synth.py` renders the app's own
/// notification chimes from (see `scene_synth.dart`, a faithful port of that
/// file's `bell`/`render`), so a module's sound and slim's own always share
/// one timbre instead of the product suddenly sounding like two apps stapled
/// together.
///
/// Never autoplayed: sound triggered by a message is something every
/// viewer's device would make on the strength of whoever posted it, so
/// [ModuleSceneView] only ever plays a `notes` op that comes back as the
/// direct result of *this* viewer's own tap, drag or control press - never
/// on a scene's first paint, and never for a scene update that arrived
/// because another viewer acted on a shared one. A person can also turn
/// module sound off entirely; see `moduleSoundSettingsProvider`.
///
/// The four ceilings below are enforced here, at parse time, not only in the
/// synthesiser: a scene is bounded before anything downstream ever sees an
/// unbounded one. See `docs/decisions/0027-module-scene-sound.md` for the
/// abuse case this whole op is scoped against.
class NotesOp extends SceneOp {
  NotesOp(List<SceneNote> notes) : notes = _bounded(notes);

  final List<SceneNote> notes;

  /// A module scene is a small UI, not a sequencer. More notes than this in
  /// one cue reads as a wall of tone rather than a sound effect, and it also
  /// bounds how much arithmetic one op can ever ask `scene_synth.dart`'s
  /// `render()` to do - the same reasoning `ModuleSceneView`'s own
  /// `_maxQueue` applies to actions.
  static const maxNotes = 32;

  /// A note ringing longer than this is the "hold a tone for an hour" abuse
  /// this ceiling exists to rule out, clamped here rather than only trusted
  /// to a well-behaved module.
  static const maxNoteSeconds = 3.0;

  /// How far into the cue a note may start. Past this a "short sound effect"
  /// has stopped being one; clamped separately from [maxNoteSeconds] so a
  /// module cannot stretch a whole cue's length by starting one note late
  /// rather than by holding it.
  static const maxSceneSeconds = 8.0;

  /// Below this a "note" reads as a sub-bass thump rather than a pitch.
  static const minFrequencyHz = 20.0;

  /// `synth.py`'s highest partial sits at 3.05x the fundamental
  /// (`_PARTIALS`); above this the app renders at 48kHz (`sampleRate` in
  /// `scene_synth.dart`), so that partial would sit past the 24kHz Nyquist
  /// limit and alias back down as noise rather than ring true.
  static const maxFrequencyHz = 7800.0;

  static List<SceneNote> _bounded(List<SceneNote> notes) => [
    for (final note in notes.take(maxNotes))
      SceneNote(
        frequency: note.frequency.clamp(minFrequencyHz, maxFrequencyHz),
        start: note.start.clamp(0.0, maxSceneSeconds),
        seconds: note.seconds.clamp(0.01, maxNoteSeconds),
      ),
  ];
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
    case 'path':
      final d = _string(op['d']);
      if (d == null) return null;
      final steps = parseScenePathData(d);
      if (steps.isEmpty) return null;
      return PathOp(
        steps: steps,
        fill: _string(op['fill']),
        stroke: _string(op['stroke']),
        strokeWidth: _double(op['sw'], 1),
        tap: _string(op['tap']),
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
    case 'notes':
      final notes = _parseNotes(op['notes']);
      return notes.isEmpty ? null : NotesOp(notes);
    default:
      return null;
  }
}

/// Each entry needs a positive frequency and duration and a non-negative
/// start; anything else is dropped rather than failing the whole op, the same
/// "skip what is bad" treatment a malformed cell or hex colour already gets.
List<SceneNote> _parseNotes(Object? raw) {
  if (raw is! List) return const [];
  final notes = <SceneNote>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final frequency = _double(entry['f'], 0);
    final start = _double(entry['t'], -1);
    final seconds = _double(entry['d'], 0);
    if (frequency <= 0 || start < 0 || seconds <= 0) continue;
    notes.add(SceneNote(frequency: frequency, start: start, seconds: seconds));
  }
  return notes;
}

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

String? _string(Object? value) => value is String ? value : null;

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];
