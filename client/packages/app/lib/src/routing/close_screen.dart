// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Leaving a screen that may be a modal.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

/// Closes this screen: pops the modal it is shown in, or falls back to
/// replacing the route when it was opened cold from a pasted URL and so has
/// nothing to pop back to.
void closeScreen(BuildContext context, String fallback) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
    return;
  }
  context.go(fallback);
}

/// The app-bar leading button for a screen that [closeScreen] closes.
///
/// Eight screens carried the identical five-line `IconButton` around this
/// call; naming it once means a change to the back affordance is one edit,
/// and no screen can drift into a different glyph or a missing tooltip.
class BackToButton extends StatelessWidget {
  const BackToButton({
    super.key,
    required this.tooltip,
    required this.fallback,
  });

  /// Names the destination ("Back to Space settings"), not just "Back": the
  /// tooltip is the only thing that says where this goes.
  final String tooltip;

  /// Where to land when there is nothing to pop; see [closeScreen].
  final String fallback;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(AppIcons.back),
    tooltip: tooltip,
    onPressed: () => closeScreen(context, fallback),
  );
}
