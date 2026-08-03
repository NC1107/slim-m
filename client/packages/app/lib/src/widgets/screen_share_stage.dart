// SPDX-License-Identifier: Apache-2.0
/// The stage a peer's shared screen renders on during a call.
///
/// Its own file rather than more of `voice_screen.dart`, which was over the
/// review budget before this existed. The video itself comes through
/// `VoiceController.screenShareViewFor`, so this file stays free of LiveKit
/// types like everything else outside the rtc package.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// A dark stage with the share inside and the sharer's name below it.
///
/// Black behind the video on purpose, in both themes: a shared screen is
/// arbitrary content, and any chrome tone bleeding around its letterbox reads
/// as part of the screen. The name line says whose screen it is, because two
/// people can share in turn and a bare rectangle does not say which.
class ScreenShareStage extends StatelessWidget {
  const ScreenShareStage({
    super.key,
    required this.sharerName,
    required this.child,
    this.isLocal = false,
  });

  final String sharerName;

  /// Whether this is the local caller's own share, so the caption reads
  /// "Your screen" rather than the caller's own name reflected back.
  final bool isLocal;

  /// The live share view, from `VoiceController.screenShareViewFor`.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
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
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Icon(AppIcons.screenShare, size: 14, color: tokens.textSecondary),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                isLocal ? 'Your screen' : "$sharerName's screen",
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
