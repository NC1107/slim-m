// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Parsing the `path` scene op's `d` string into steps slim can paint.
///
/// Its own file rather than more of `module_scene.dart`: that file is the
/// scene model and one small parser per op, and this is a tokeniser for a
/// miniature language. Keeping it here also means the op's ceilings live next
/// to the loop that could otherwise run away.
///
/// The grammar is the useful subset of SVG's: `M`/`L`/`H`/`V`/`C`/`Q`/`Z`,
/// lowercase for relative. Arcs (`A`) and smooth continuations (`S`/`T`) are
/// deliberately absent - each needs state or trigonometry that a module can
/// express with the curves already here, and every command admitted is one
/// more thing a malformed string can do.
///
/// Nothing here throws. A `d` that stops making sense is truncated at that
/// point and whatever parsed before it is kept, the same "skip what is bad"
/// treatment a malformed cell or hex colour already gets.
library;

import 'dart:ui';

/// What one step of a path does. The numbers each kind expects are in
/// [ScenePathStep.points], already in the scene's own logical units.
enum ScenePathKind {
  /// Lift the pen and start a new subpath. Two numbers.
  move,

  /// Straight line to a point. Two numbers.
  line,

  /// Quadratic bezier: one control point then the end point. Four numbers.
  quad,

  /// Cubic bezier: two control points then the end point. Six numbers.
  cubic,

  /// Close the current subpath back to where it started. No numbers.
  close,
}

class ScenePathStep {
  const ScenePathStep(this.kind, this.points);

  final ScenePathKind kind;
  final List<double> points;
}

/// How many steps one path may carry.
///
/// A scene is a small drawing, and a path is the one op whose cost is set by
/// the length of a string rather than by a count the module states up front.
/// This is the same bounding instinct `NotesOp.maxNotes` applies to sound: a
/// ceiling at parse time, so nothing downstream ever holds an unbounded path.
const sceneMaxPathSteps = 512;

/// Turns an SVG-style `d` string into steps, or an empty list if none of it
/// parsed. Bounded by [sceneMaxPathSteps].
List<ScenePathStep> parseScenePathData(String d) {
  final tokens = _tokenise(d);
  final steps = <ScenePathStep>[];
  var i = 0;
  // The pen, and the subpath start that close returns it to.
  var x = 0.0;
  var y = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  String? command;

  while (i < tokens.length && steps.length < sceneMaxPathSteps) {
    final token = tokens[i];
    if (token is String) {
      command = token;
      i++;
      if (command == 'Z' || command == 'z') {
        steps.add(const ScenePathStep(ScenePathKind.close, []));
        x = startX;
        y = startY;
      }
      continue;
    }
    if (command == null) return steps;

    final needed = _argumentCount(command);
    if (needed == 0) return steps;
    final args = _numbers(tokens, i, needed);
    if (args == null) return steps;
    i += needed;
    final relative = command == command.toLowerCase();

    switch (command.toUpperCase()) {
      case 'M':
        x = relative ? x + args[0] : args[0];
        y = relative ? y + args[1] : args[1];
        startX = x;
        startY = y;
        steps.add(ScenePathStep(ScenePathKind.move, [x, y]));
        // A repeated coordinate pair after M is an implicit L, as in SVG.
        command = relative ? 'l' : 'L';
      case 'L':
        x = relative ? x + args[0] : args[0];
        y = relative ? y + args[1] : args[1];
        steps.add(ScenePathStep(ScenePathKind.line, [x, y]));
      case 'H':
        x = relative ? x + args[0] : args[0];
        steps.add(ScenePathStep(ScenePathKind.line, [x, y]));
      case 'V':
        y = relative ? y + args[0] : args[0];
        steps.add(ScenePathStep(ScenePathKind.line, [x, y]));
      case 'Q':
        final cx = relative ? x + args[0] : args[0];
        final cy = relative ? y + args[1] : args[1];
        x = relative ? x + args[2] : args[2];
        y = relative ? y + args[3] : args[3];
        steps.add(ScenePathStep(ScenePathKind.quad, [cx, cy, x, y]));
      case 'C':
        final c1x = relative ? x + args[0] : args[0];
        final c1y = relative ? y + args[1] : args[1];
        final c2x = relative ? x + args[2] : args[2];
        final c2y = relative ? y + args[3] : args[3];
        x = relative ? x + args[4] : args[4];
        y = relative ? y + args[5] : args[5];
        steps.add(
          ScenePathStep(ScenePathKind.cubic, [c1x, c1y, c2x, c2y, x, y]),
        );
      default:
        return steps;
    }
  }
  return steps;
}

/// How many numbers a command consumes per repetition, or 0 if it is not one
/// this grammar draws with.
int _argumentCount(String command) => switch (command.toUpperCase()) {
  'M' || 'L' => 2,
  'H' || 'V' => 1,
  'Q' => 4,
  'C' => 6,
  _ => 0,
};

/// [count] numbers starting at [from], or null if they are not all there.
List<double>? _numbers(List<Object> tokens, int from, int count) {
  if (from + count > tokens.length) return null;
  final out = <double>[];
  for (var i = from; i < from + count; i++) {
    final token = tokens[i];
    if (token is! double) return null;
    out.add(token);
  }
  return out;
}

/// Splits [d] into command letters and numbers. Separators are insignificant,
/// as in SVG: commas, whitespace, and the sign or decimal point that starts a
/// new number all end the one before it.
List<Object> _tokenise(String d) {
  final tokens = <Object>[];
  final number = StringBuffer();

  void flush() {
    if (number.isEmpty) return;
    final parsed = double.tryParse(number.toString());
    if (parsed != null && parsed.isFinite) tokens.add(parsed);
    number.clear();
  }

  for (var i = 0; i < d.length; i++) {
    final c = d[i];
    if (_isCommand(c)) {
      flush();
      tokens.add(c);
    } else if (c == ',' || c.trim().isEmpty) {
      flush();
    } else if (c == '-' || c == '+') {
      // A sign mid-number starts the next one, unless it follows an exponent.
      final previous = number.isEmpty ? '' : number.toString();
      if (previous.isNotEmpty &&
          !previous.endsWith('e') &&
          !previous.endsWith('E')) {
        flush();
      }
      number.write(c);
    } else if (c == '.' && number.toString().contains('.')) {
      flush();
      number.write(c);
    } else {
      number.write(c);
    }
  }
  flush();
  return tokens;
}

/// Whether [c] starts a command rather than a number.
///
/// Any letter counts, not only the ones this grammar draws with, so an SVG
/// command it does not admit (`A`, `S`, `T`) truncates the path at that point
/// instead of being swallowed into a number. Swallowing it was worse than
/// refusing it: the letter parsed to nothing and its arguments were then
/// consumed by whichever command came before, which drew a mangled shape
/// rather than a short one.
///
/// `e` and `E` are the exception, because they appear inside a number as an
/// exponent and nowhere else.
bool _isCommand(String c) {
  if (c == 'e' || c == 'E') return false;
  final code = c.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
}

/// Builds a painted path from [steps], scaling the scene's logical units by
/// [sx]/[sy] the same way every other op is scaled.
///
/// A path that starts with a curve or a line rather than a move begins at the
/// origin, which is what `Path` does on its own; nothing here has to guard it.
Path buildScenePath(List<ScenePathStep> steps, double sx, double sy) {
  final path = Path();
  for (final step in steps) {
    final p = step.points;
    switch (step.kind) {
      case ScenePathKind.move:
        path.moveTo(p[0] * sx, p[1] * sy);
      case ScenePathKind.line:
        path.lineTo(p[0] * sx, p[1] * sy);
      case ScenePathKind.quad:
        path.quadraticBezierTo(p[0] * sx, p[1] * sy, p[2] * sx, p[3] * sy);
      case ScenePathKind.cubic:
        path.cubicTo(
          p[0] * sx,
          p[1] * sy,
          p[2] * sx,
          p[3] * sy,
          p[4] * sx,
          p[5] * sy,
        );
      case ScenePathKind.close:
        path.close();
    }
  }
  return path;
}
