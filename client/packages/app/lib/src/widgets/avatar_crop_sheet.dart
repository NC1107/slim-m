// SPDX-License-Identifier: Apache-2.0
/// Square-crops a picked image before it is uploaded as an avatar.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:slimm_design_system/design_system.dart';

/// The edge of the encoded result, in pixels.
///
/// A phone photo is routinely 3 to 5 MB and the server caps an avatar at 2 MB,
/// so uploading the picked file unchanged failed for most real pictures. This
/// re-encodes at a size an avatar is ever drawn at, which lands far under the
/// cap as a side effect of doing the crop the user asked for.
const int _outputEdge = 512;

/// Shows [bytes] in a square viewport the user can pan and zoom, and returns
/// the cropped PNG, or null if they backed out.
Future<Uint8List?> showAvatarCropSheet(BuildContext context, Uint8List bytes) {
  return showAppSheet<Uint8List>(
    context,
    maxWidth: 520,
    builder: (_) => _AvatarCropSheet(bytes: bytes),
  );
}

class _AvatarCropSheet extends StatefulWidget {
  const _AvatarCropSheet({required this.bytes});

  final Uint8List bytes;

  @override
  State<_AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<_AvatarCropSheet> {
  final _boundary = GlobalKey();
  final _controller = TransformationController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Captures the viewport rather than reading the pan and zoom back out of
  /// the transform: what is inside the square is exactly what was shown, with
  /// no second implementation of the same geometry to disagree with it.
  Future<void> _confirm() async {
    setState(() => _busy = true);
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ratio = _outputEdge / object.size.width;
    final image = await object.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (!mounted) return;
    Navigator.of(context).pop(data?.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // The viewport is square, so it has to fit the shorter side as well.
    // Sized on width alone it was 1248pt tall in a 900pt window, which pushed
    // Cancel and Use picture off the bottom of the screen on every desktop.
    final size = MediaQuery.sizeOf(context);
    final edge = math.min(size.width - AppSpacing.s32, size.height * 0.5);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Crop your picture', style: AppText.title),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Drag to move, pinch to zoom.',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s16),
            ClipOval(
              child: RepaintBoundary(
                key: _boundary,
                child: SizedBox(
                  width: edge,
                  height: edge,
                  child: InteractiveViewer(
                    transformationController: _controller,
                    minScale: 1,
                    maxScale: 5,
                    clipBehavior: Clip.hardEdge,
                    child: Image.memory(
                      widget.bytes,
                      fit: BoxFit.cover,
                      width: edge,
                      height: edge,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.ghost,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: AppButton(
                    label: _busy ? 'Working...' : 'Use picture',
                    variant: AppButtonVariant.primary,
                    onPressed: _busy ? null : _confirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
