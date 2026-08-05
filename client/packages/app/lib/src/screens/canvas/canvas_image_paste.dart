// SPDX-License-Identifier: Apache-2.0
/// Pastes a clipboard image onto the canvas: decode, upload, place, and
/// attach the decoded bitmap directly - the bytes this call already holds
/// in memory, never re-fetched from the server it was just sent to.
///
/// Reuses the composer's own clipboard seam (`composer_clipboard_paste.dart`)
/// rather than a second one: `hasClipboardImage`/`readClipboardImage` are
/// real on iOS, Android and Linux desktop, and `startClipboardImagePaste` is
/// the same event-driven route the composer's long-press-and-Paste flow uses
/// on iOS and web. Nothing here is composer-specific in its signature, so
/// there is no new platform channel and no new native code.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../ids.dart';
import '../../widgets/composer_clipboard_image.dart';
import '../../widgets/composer_clipboard_paste.dart';
import 'canvas_sync.dart';

/// Longest side, in world units, a pasted image is scaled to fit within.
/// Well under `MAX_OBJECT_EXTENT` (8192), and generous enough that a normal
/// screenshot lands at a size worth looking at without dwarfing the board;
/// an image smaller than this is never scaled up.
const double maxPastedImageSide = 1024;

/// Owns every route a clipboard image can reach this pane through - a
/// toolbar button, Ctrl+V, and the native edit-menu/DOM listener - and what
/// happens once bytes arrive: decode, upload, place.
class CanvasImagePaste {
  CanvasImagePaste({
    required this.client,
    required this.channelId,
    required this.document,
    required this.onPlaced,
    required this.onError,
  });

  final api.SlimmApi client;
  final String channelId;
  final CanvasDocument document;

  /// Called once a paste is placed and confirmed, so the caller can switch
  /// to the select tool - the one thing worth doing immediately after.
  final VoidCallback onPlaced;

  /// A sentence to show, or null to clear a previously shown one.
  final void Function(String? message) onError;

  /// Registers the event-driven route: call once when this pane mounts.
  void start() => startClipboardImagePaste(_handleNativePaste);

  /// Unregisters it: call once when this pane unmounts. Passing
  /// [_handleNativePaste] back is what lets `stopClipboardImagePaste` tell
  /// this call apart from a *different* caller's still-active registration
  /// - see that function's own doc for the race a bare, argument-less stop
  /// used to lose.
  void stop() => stopClipboardImagePaste(_handleNativePaste);

  /// The toolbar's "Paste image" action: the manual poll-and-tap route that
  /// works unconditionally on every platform, the same fallback the
  /// composer's own "+" sheet row is.
  Future<void> pasteFromButton() => pasteClipboardImage(_stage, onError);

  /// The Ctrl+V/Cmd+V route: a no-op wherever
  /// `pasteKeystrokeReadsClipboardImage` is false (iOS, which has the native
  /// route below instead).
  Future<void> pasteFromKeystroke() =>
      pasteClipboardImageFromKeystroke(_stage, onError);

  void _handleNativePaste(Uint8List bytes, String filename) =>
      unawaited(_stage(bytes, filename));

  Future<void> _stage(Uint8List bytes, String filename) async {
    final placed = await _place(bytes);
    if (placed != null) onPlaced();
  }

  /// Decodes [bytes], uploads them, and places an image object centered on
  /// the document's current view. On success, applies the placed object and
  /// hands it the already-decoded bitmap directly - no second fetch and
  /// decode of what this call already holds.
  Future<api.CanvasObject?> _place(Uint8List bytes) async {
    onError(null);
    final ui.Image decoded;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      decoded = frame.image;
    } catch (_) {
      onError('That image could not be read.');
      return null;
    }

    final api.Attachment attachment;
    try {
      attachment = await client.uploadAttachment(
        bytes,
        filename: 'pasted-image.png',
      );
    } on api.ApiException {
      decoded.dispose();
      onError('That image could not be uploaded.');
      return null;
    }

    final scale = _fitScale(decoded.width, decoded.height);
    final w = decoded.width * scale;
    final h = decoded.height * scale;
    final center = document.worldView.center;
    final x = center.dx - w / 2;
    final y = center.dy - h / 2;

    final api.CanvasObject placed;
    try {
      placed = await client.placeCanvasObject(
        channelId,
        id: newCanvasObjectId(),
        kind: 'image',
        x: x,
        y: y,
        w: w,
        h: h,
        props: {
          'attachment': attachment.id,
          'content_type': attachment.contentType,
          'width': decoded.width,
          'height': decoded.height,
        },
      );
    } on api.ApiException catch (error) {
      decoded.dispose();
      onError(_explain(error));
      return null;
    }

    final input = canvasStrokeInputFrom(placed);
    if (input == null) {
      // Never expected, but a decode mismatch here must not leak the bitmap.
      decoded.dispose();
      return placed;
    }
    document
      ..applyPlaced(input)
      ..setImageBitmap(placed.id, decoded)
      ..refresh();
    return placed;
  }

  static double _fitScale(int naturalWidth, int naturalHeight) {
    final longest = math.max(naturalWidth, naturalHeight).toDouble();
    if (longest <= maxPastedImageSide || longest == 0) return 1;
    return maxPastedImageSide / longest;
  }

  static String _explain(api.ApiException error) => switch (error) {
    api.ForbiddenException() => 'You cannot draw on this canvas right now.',
    api.ConflictException() => 'This canvas is full.',
    api.BadRequestException() => 'That image was refused.',
    _ => 'That image could not be pasted.',
  };
}
