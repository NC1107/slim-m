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

class CameraSelfPreview extends StatelessWidget {
  const CameraSelfPreview({super.key, required this.child});

  /// The live view, from `VoiceController.cameraViewFor`.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Black behind the video, same reason as `ScreenShareStage`'s letterbox.
    return Center(
      child: SizedBox(
        width: 220,
        height: 165,
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
    );
  }
}
