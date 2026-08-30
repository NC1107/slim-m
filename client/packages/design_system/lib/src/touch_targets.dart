// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The input-class signal behind every control's `touch` flag.
library;

import 'package:flutter/widgets.dart';

import 'app_metrics.dart';

/// Whether controls in this subtree should meet [AppSizes.rowTouch] rather
/// than [AppSizes.rowPointer].
///
/// Every control with a `touch` flag ([AppIconButton], [AppButton],
/// [AppListRow], [AppMenuItem]) resolves it through [of] when the caller
/// leaves it unset, so the density of a screen is decided once rather than at
/// each of its several dozen call sites. A control that must hold one density
/// whatever it is placed in still passes the flag itself, and that wins.
///
/// This exists because the flag alone did not work: it was built, documented
/// and tested, and every call site in the client forgot it, which left a
/// phone rendering 30pt targets against a 44pt platform minimum.
class AppTouchTargets extends InheritedWidget {
  const AppTouchTargets({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  /// An enclosing [AppTouchTargets] if there is one, otherwise the window
  /// width against [kCompactWidth].
  ///
  /// Falling back to width rather than to a hardcoded `false` is what makes
  /// this unforgettable: a control is at touch density on a phone because of
  /// where it is drawn, not because someone remembered to say so. Width, not
  /// platform, for the reason `LayoutClass` gives: a phone in landscape, a
  /// small desktop window and a split-screen tablet are the same problem.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppTouchTargets>();
    if (scope != null) return scope.enabled;
    final width = MediaQuery.maybeSizeOf(context)?.width;
    return width != null && width < kCompactWidth;
  }

  @override
  bool updateShouldNotify(AppTouchTargets oldWidget) =>
      oldWidget.enabled != enabled;
}
