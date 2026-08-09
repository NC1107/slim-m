// SPDX-License-Identifier: Apache-2.0
/// A tapped image, opened over the app: pinch to zoom, drag to pan, and
/// either a swipe down or the close control to leave.
///
/// It is handed bytes rather than an attachment id, so it cannot start a
/// second fetch. `attachmentBytesProvider` is `autoDispose`, the only way in
/// is a tap on an image already showing those exact bytes, and passing them
/// down is what makes "still loading" and "a fetch failed" unreachable states
/// here rather than a black screen with nothing on it.
///
/// A decode failure is reachable, though: `AttachmentView`'s own inline
/// thumbnail offers this route as its only tap target even once its bytes
/// have already failed to decode there, so the same bytes are tried again
/// here rather than assuming they will now succeed - [_DecodeFailure] is
/// what stops that retry from surfacing as an uncaught exception.
///
/// No `Hero`. An attachment is content-addressed, so one id legitimately
/// rides on more than one message (`models_attachments.dart`), and two rows
/// showing the same image would put two identical hero tags in one subtree,
/// which throws. `AttachmentView` is given no message id to disambiguate a
/// tag with, so the flight is traded for a fade.
///
/// The backdrop is black in both themes: a surface token would tint the
/// letterbox around a photo, and the controls are themed dark to match rather
/// than following the app's brightness.
///
/// This route is pushed on the root navigator, above any Scaffold, so
/// nothing upstream supplies the [Material] ancestor [Text] and [Icon] rely
/// on for their default style; without one Flutter renders them in its own
/// debug fallback (red text, a double yellow underline) rather than the
/// theme's, which reads as a colour bug and is not one. `build` below wraps
/// its content in a transparent [Material] for exactly this reason.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// How large the floating viewer is allowed to get on a desktop window.
const double kViewerMaxWidth = 1100;
const double kViewerMaxHeight = 820;

/// Opens [bytes] fullscreen. Non-opaque so the conversation behind stays
/// visible through the fade rather than the route cutting to black.
Future<void> showFullscreenImage(
  BuildContext context, {
  required String filename,
  required Uint8List bytes,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: AppMotion.reduced(
        context,
        const Duration(milliseconds: 160),
      ),
      reverseTransitionDuration: AppMotion.reduced(
        context,
        const Duration(milliseconds: 120),
      ),
      pageBuilder: (_, animation, _) => FadeTransition(
        opacity: animation,
        child: FullscreenImageViewer(filename: filename, bytes: bytes),
      ),
    ),
  );
}

class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.filename,
    required this.bytes,
  });

  final String filename;
  final Uint8List bytes;

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  static const double _maxScale = 8;
  static const double _zoomedAbove = 1.01;
  static const double _dismissDistance = 96;
  static const double _dismissVelocity = 700;

  final TransformationController _transform = TransformationController();
  bool _zoomed = false;
  double _dragged = 0;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_syncZoom);
  }

  @override
  void dispose() {
    _transform.removeListener(_syncZoom);
    _transform.dispose();
    super.dispose();
  }

  void _syncZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > _zoomedAbove;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _dragged = math.max(0, _dragged + details.delta.dy));
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragged >= _dismissDistance || velocity >= _dismissVelocity) {
      _close();
      return;
    }
    setState(() => _dragged = 0);
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    // Zoomed, every drag belongs to the viewer's own pan; the dismiss
    // gesture would otherwise steal it and leave the image un-pannable.
    final dismissible = !_zoomed;
    // A phone gives the image the whole window, which is the point of opening
    // it. A desktop window has room to keep the app visible around it, so the
    // image floats in a panel and a click beside it puts the image away.
    final compact = MediaQuery.sizeOf(context).width < kCompactWidth;
    return Theme(
      data: buildTheme(Brightness.dark, AppTokens.dark),
      // Material ancestor for Text/Icon; see this file's library doc.
      child: Material(
        type: MaterialType.transparency,
        child: _Backdrop(
          compact: compact,
          onDismiss: _close,
          child: SafeArea(
            child: Column(
              children: [
                _ViewerHeader(filename: widget.filename, onClose: _close),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: dismissible ? _onDragUpdate : null,
                    onVerticalDragEnd: dismissible ? _onDragEnd : null,
                    child: Transform.translate(
                      offset: Offset(0, _dragged),
                      child: InteractiveViewer(
                        transformationController: _transform,
                        maxScale: _maxScale,
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.contain,
                          semanticLabel: widget.filename,
                          // The inline thumbnail already tried and failed to decode these same bytes; see this widget's own doc comment.
                          errorBuilder: (context, error, stackTrace) =>
                              _DecodeFailure(filename: widget.filename),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What renders in place of the image when the bytes this viewer was handed
/// fail to decode, on the dark theme [FullscreenImageViewer] always applies.
class _DecodeFailure extends StatelessWidget {
  const _DecodeFailure({required this.filename});

  final String filename;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Text(
          'Could not open $filename.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: tokens.textSecondary),
        ),
      ),
    );
  }
}

class _ViewerHeader extends StatelessWidget {
  const _ViewerHeader({required this.filename, required this.onClose});

  final String filename;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.ui.copyWith(color: tokens.textSecondary),
            ),
          ),
          AppIconButton(
            icon: AppIcons.dismiss,
            semanticLabel: 'Close image',
            size: AppIconButtonSize.touch,
            touch: true,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// The dark field the image sits on, and what a click on it means.
///
/// On a phone it is the window and a click on it does nothing, because there
/// is no "outside" to click: the drag gesture is how the image is dismissed.
/// On a desktop window it is a scrim around a floating panel, and clicking it
/// closes the viewer the way clicking beside any modal does.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.compact,
    required this.onDismiss,
    required this.child,
  });

  final bool compact;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    if (compact) {
      return ColoredBox(
        color: Colors.black.withValues(alpha: 0.94),
        child: child,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.72)),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kViewerMaxWidth,
              maxHeight: kViewerMaxHeight,
            ),
            // Swallows the taps that land on the panel, so only a click that
            // reaches the scrim behind it counts as clicking outside.
            child: GestureDetector(
              onTap: () {},
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.94),
                    border: Border.all(color: tokens.borderSubtle),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
