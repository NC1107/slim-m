// SPDX-License-Identifier: Apache-2.0
/// A small live preview of your own camera, shown whenever it is on.
///
/// Turning a camera on alone in a call - or with everybody else's camera
/// off - used to show nothing at all, since there was no viewer for a
/// camera track, local or remote. `ScreenShareStage` already covers the
/// equivalent gap for a shared screen; this is the camera half.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'fullscreen_video_overlay.dart';

class CameraSelfPreview extends StatelessWidget {
  const CameraSelfPreview({super.key, required this.child, this.onExpand});

  /// The live view, from `VoiceController.cameraViewFor`.
  final Widget child;

  /// Opens this preview full screen. Null only in the tests that build this
  /// widget in isolation with nothing behind it to expand into.
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Black behind the video, same reason as `ScreenShareStage`'s letterbox.
    return Center(
      child: SizedBox(
        width: 220,
        height: 165,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    border: Border.all(color: tokens.borderSubtle),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: child,
                ),
              ),
            ),
            if (onExpand != null)
              Positioned(
                left: 4,
                top: 4,
                child: ExpandVideoButton(
                  label: 'View your camera full screen',
                  onTap: onExpand!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
