// SPDX-License-Identifier: Apache-2.0
/// Leaving a screen that may be a modal.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
