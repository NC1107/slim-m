// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Puts [UpdateAvailableBanner] above the app on the layouts that have
/// nowhere else to hang it.
///
/// On desktop the banner already lives in `DesktopChrome`, outside the router
/// entirely, so this hands the child straight back rather than mounting a
/// second one - two banners saying the same thing is worse than none.
///
/// Everywhere else the signed-in shell is the outermost thing there is, which
/// is why this wrapper exists at all. The banner is only ever visible when
/// `update_watch.dart` has actually found something, so on a platform that
/// never polls this costs one `SizedBox.shrink` in the tree.
///
/// The `SafeArea` is deliberately top-only: the scaffold underneath already
/// insets its own body, and a banner painted above it would otherwise sit
/// under the status bar or a notch.
library;

import 'package:flutter/material.dart';
import 'package:slimm_platform/platform.dart';

import '../desktop/update_available_banner.dart';

class UpdateBannerHost extends StatelessWidget {
  const UpdateBannerHost({super.key, required this.child, this.ownsBanner});

  final Widget child;

  /// Whether some outer chrome already mounts the banner. The real answer is
  /// [isDesktopHost], which a test host cannot fake, so it is overridable the
  /// same way the banner's own `restartApplies` is.
  final bool? ownsBanner;

  @override
  Widget build(BuildContext context) {
    if (ownsBanner ?? isDesktopHost) return child;
    return Column(
      children: [
        const SafeArea(bottom: false, child: UpdateAvailableBanner()),
        Expanded(child: child),
      ],
    );
  }
}
