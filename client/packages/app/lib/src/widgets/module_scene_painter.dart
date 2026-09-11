// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Paints a [ModuleScene] and answers "what did a tap land on", the two
/// halves of rendering a module's scene. Both scale the scene's logical
/// coordinates to whatever box the widget is given, and both resolve named
/// colours against the viewer's theme so a module's drawing is native to
/// light and dark without the module choosing either.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'module_scene.dart';

class ModuleScenePainter extends CustomPainter {
  const ModuleScenePainter({required this.scene, required this.tokens});

  final ModuleScene scene;
  final AppTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = scene.width == 0 ? 1.0 : size.width / scene.width;
    final sy = scene.height == 0 ? 1.0 : size.height / scene.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _resolve(scene.background, tokens.surfaceRaised),
    );
    for (final op in scene.ops) {
      _paintOp(canvas, op, sx, sy);
    }
  }

  void _paintOp(Canvas canvas, SceneOp op, double sx, double sy) {
    switch (op) {
      case CellsOp():
        _paintCells(canvas, op, sx, sy);
      case RectOp():
        final rect = Rect.fromLTWH(op.x * sx, op.y * sy, op.w * sx, op.h * sy);
        final rrect = RRect.fromRectAndRadius(
          rect,
          Radius.circular(op.radius * sx),
        );
        if (op.fill != null) {
          canvas.drawRRect(
            rrect,
            Paint()..color = _resolve(op.fill, tokens.accent),
          );
        }
        _stroke(
          canvas,
          op.stroke,
          op.strokeWidth * sx,
          (p) => canvas.drawRRect(rrect, p),
        );
      case CircleOp():
        final center = Offset(op.cx * sx, op.cy * sy);
        final radius = op.r * ((sx + sy) / 2);
        if (op.fill != null) {
          canvas.drawCircle(
            center,
            radius,
            Paint()..color = _resolve(op.fill, tokens.accent),
          );
        }
        _stroke(
          canvas,
          op.stroke,
          op.strokeWidth * sx,
          (p) => canvas.drawCircle(center, radius, p),
        );
      case LineOp():
        _stroke(
          canvas,
          op.stroke ?? 'muted',
          op.strokeWidth * sx,
          (p) => canvas.drawLine(
            Offset(op.x1 * sx, op.y1 * sy),
            Offset(op.x2 * sx, op.y2 * sy),
            p,
          ),
        );
      case TextOp():
        _paintText(canvas, op, sx, sy);
    }
  }

  void _paintCells(Canvas canvas, CellsOp op, double sx, double sy) {
    if (op.cols <= 0 || op.rows <= 0 || op.palette.isEmpty) return;
    final cellW = (scene.width / op.cols) * sx;
    final cellH = (scene.height / op.rows) * sy;
    final inset = op.gap * (cellW < cellH ? cellW : cellH) / 2;
    final colors = op.palette
        .map((name) => _resolve(name, tokens.surfaceSunken))
        .toList(growable: false);
    for (var i = 0; i < op.data.length && i < op.cols * op.rows; i++) {
      final index = op.data.codeUnitAt(i) - 0x30;
      if (index < 0 || index >= colors.length) continue;
      final col = i % op.cols;
      final row = i ~/ op.cols;
      final rect = Rect.fromLTWH(
        col * cellW + inset,
        row * cellH + inset,
        cellW - inset * 2,
        cellH - inset * 2,
      );
      canvas.drawRect(rect, Paint()..color = colors[index]);
    }
  }

  void _paintText(Canvas canvas, TextOp op, double sx, double sy) {
    final painter = TextPainter(
      text: TextSpan(
        text: op.text,
        style: TextStyle(
          color: _resolve(op.fill, tokens.textPrimary),
          fontSize: op.size * sy,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (op.align) {
      'center' => op.x * sx - painter.width / 2,
      'right' => op.x * sx - painter.width,
      _ => op.x * sx,
    };
    painter.paint(canvas, Offset(dx, op.y * sy - painter.height / 2));
  }

  void _stroke(
    Canvas canvas,
    String? color,
    double width,
    void Function(Paint) draw,
  ) {
    if (color == null) return;
    draw(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width <= 0 ? 1 : width
        ..color = _resolve(color, tokens.borderSubtle),
    );
  }

  Color _resolve(String? name, Color fallback) =>
      resolveSceneColor(name, tokens, fallback);

  @override
  bool shouldRepaint(ModuleScenePainter old) =>
      !identical(old.scene, scene) || old.tokens != tokens;
}

/// Maps a scene colour name to a real colour: a `#rgb`/`#rrggbb`/`#aarrggbb`
/// literal is parsed as written; a theme-token name resolves against [tokens];
/// anything unrecognised falls back to [fallback].
Color resolveSceneColor(String? name, AppTokens tokens, Color fallback) {
  if (name == null || name.isEmpty) return fallback;
  if (name.startsWith('#')) return _parseHex(name) ?? fallback;
  return switch (name) {
    'bg' => tokens.surfaceBase,
    'surface' => tokens.surfaceRaised,
    'sunken' => tokens.surfaceSunken,
    'accent' => tokens.accent,
    'accent-soft' => tokens.accentSoft,
    'muted' => tokens.textSecondary,
    'text' => tokens.textPrimary,
    'border' => tokens.borderSubtle,
    'danger' => tokens.dangerText,
    _ => fallback,
  };
}

Color? _parseHex(String value) {
  var hex = value.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'ff$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// The action a tap at [local] within a [size]-sized box lands on, or null if
/// it hit nothing interactive. Ops are tested topmost-first. A tap on a
/// [CellsOp] reports the specific cell as `"$tap:row,col"`; a tap on a [RectOp]
/// or [CircleOp] reports its bare `tap`.
/// Whether [action] came from a cells op that reads a `;`-separated list, so
/// several of them may be sent as one call. False for anything else, including
/// a scene from a module that has never heard of batching.
bool sceneAllowsTapBatch(ModuleScene scene, String action) {
  final prefix = action.split(':').first;
  for (final op in scene.ops) {
    if (op is CellsOp && op.tap == prefix) return op.tapBatch;
  }
  return false;
}

String? sceneTapAction(ModuleScene scene, Offset local, Size size) {
  final sx = scene.width == 0 ? 1.0 : size.width / scene.width;
  final sy = scene.height == 0 ? 1.0 : size.height / scene.height;
  for (final op in scene.ops.reversed) {
    switch (op) {
      case CellsOp() when op.tap != null && op.cols > 0 && op.rows > 0:
        final col = (local.dx / (size.width / op.cols)).floor();
        final row = (local.dy / (size.height / op.rows)).floor();
        if (col >= 0 && col < op.cols && row >= 0 && row < op.rows) {
          return '${op.tap}:$row,$col';
        }
      case RectOp() when op.tap != null:
        final rect = Rect.fromLTWH(op.x * sx, op.y * sy, op.w * sx, op.h * sy);
        if (rect.contains(local)) return op.tap;
      case CircleOp() when op.tap != null:
        final center = Offset(op.cx * sx, op.cy * sy);
        if ((local - center).distance <= op.r * ((sx + sy) / 2)) return op.tap;
      default:
        break;
    }
  }
  return null;
}
