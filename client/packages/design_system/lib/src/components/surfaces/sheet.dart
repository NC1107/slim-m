// SPDX-License-Identifier: Apache-2.0
/// One way to ask for a modal, presented as whatever the window can carry.
///
/// A bottom sheet is a phone affordance: it sits against the edge a thumb can
/// reach, and its drag handle means something to a thumb. On a desktop window
/// it reads as a phone screen pasted along the bottom of a monitor, offers a
/// handle a mouse cannot usefully drag, and gets cut off by the bottom of the
/// window when the content is tall. Every modal in the app was one.
///
/// So the same call gives a sheet on a phone and a centred dialog on anything
/// wider, and the caller does not choose: the window does.
library;

import 'package:flutter/material.dart';

import '../../app_metrics.dart';
import '../../app_tokens.dart';

/// How wide a dialog is allowed to get, when it is one.
///
/// A form does not become more readable by growing with the monitor, and a
/// modal that spans a wide screen stops reading as a modal at all.
const double kSheetMaxWidth = 460;

/// Shows [builder] as a bottom sheet on a phone and a dialog on a desktop.
///
/// [maxWidth] widens the dialog for content that genuinely needs it, a grid of
/// emoji rather than a form. [scrolls] says the content already scrolls, so it
/// is given a bounded height and left to manage it; the default wraps it,
/// which is right for the columns most of these are. [bare] is for content
/// that already draws its own surface, an [AppMenu] being the case: without it
/// the dialog's panel and the menu's panel nest, one border inside another.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = kSheetMaxWidth,
  bool scrolls = false,
  bool bare = false,
}) {
  if (MediaQuery.sizeOf(context).width < kCompactWidth) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => _SheetDialog(
      maxWidth: maxWidth,
      scrolls: scrolls,
      bare: bare,
      child: Builder(builder: builder),
    ),
  );
}

class _SheetDialog extends StatelessWidget {
  const _SheetDialog({
    required this.maxWidth,
    required this.scrolls,
    required this.bare,
    required this.child,
  });

  final double maxWidth;
  final bool scrolls;
  final bool bare;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Never taller than the window, whatever the content asks for: the bottom
    // sheet's failure was being cut off by an edge it could not see.
    final ceiling = MediaQuery.sizeOf(context).height * 0.85;

    return Dialog(
      backgroundColor: bare ? Colors.transparent : tokens.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: bare ? 0 : null,
      insetPadding: const EdgeInsets.all(AppSpacing.s24),
      shape: bare
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(color: tokens.borderSubtle),
            ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: ceiling),
        child: scrolls
            ? child
            : SingleChildScrollView(
                child: child,
              ),
      ),
    );
  }
}
