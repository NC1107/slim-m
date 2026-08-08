// SPDX-License-Identifier: Apache-2.0
/// The two kinds of content a presence tile can show - a camera and an
/// avatar fallback, or a screen share - split out of `canvas_presence_layer
/// .dart` once wiring screen share and manipulation pushed it past the
/// 300-line review budget. Purely visual: neither widget here knows it is
/// draggable, resizable, lockable or hideable - that is
/// `canvas_presence_tile.dart`'s `CanvasPresenceManipulableTile`, which
/// wraps whichever of these two it is given.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../../widgets/user_avatar.dart';

/// One participant's camera tile: their live camera when it is on, an
/// avatar with the usual speaking ring otherwise - `CallParticipantTile`'s
/// own fallback, reused rather than redrawn.
class CanvasPresenceBubble extends StatelessWidget {
  const CanvasPresenceBubble({
    super.key,
    required this.participant,
    this.cameraView,
  });

  final VoiceParticipant participant;
  final Widget? cameraView;

  bool get _showsCamera => cameraView != null && participant.isCameraOn;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return _TileChrome(
      tokens: tokens,
      body: _showsCamera
          ? DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFF000000)),
              child: cameraView,
            )
          : UserAvatar(
              name: participant.name,
              userId: participant.identity,
              size: 56,
              speaking: participant.isSpeaking,
            ),
      badge: _NameBadge(
        name: participant.isLocal
            ? '${participant.name} (you)'
            : participant.name,
        muted: participant.isMuted,
      ),
    );
  }
}

/// A screen-share tile: no speaking ring or mic glyph, since sharing a
/// screen carries no audio state of its own worth badging - only whose
/// screen it is.
class CanvasScreenShareBubble extends StatelessWidget {
  const CanvasScreenShareBubble({
    super.key,
    required this.participant,
    required this.view,
  });

  final VoiceParticipant participant;
  final Widget view;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return _TileChrome(
      tokens: tokens,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF000000)),
        child: view,
      ),
      badge: _NameBadge(
        name: participant.isLocal
            ? 'Your screen'
            : "${participant.name}'s screen",
        icon: AppIcons.screenShare,
      ),
    );
  }
}

class _TileChrome extends StatelessWidget {
  const _TileChrome({required this.tokens, required this.body, this.badge});

  final AppTokens tokens;
  final Widget body;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Container(
    // AppRadii.window and AppShadows.float: reserved, by their own docs, for exactly a floating canvas object.
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadii.window),
      boxShadow: AppShadows.float,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.window),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: body),
            if (badge != null) Positioned(left: 6, bottom: 6, child: badge!),
          ],
        ),
      ),
    ),
  );
}

class _NameBadge extends StatelessWidget {
  const _NameBadge({required this.name, this.muted, this.icon});

  final String name;
  final bool? muted;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceBase.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? (muted == true ? AppIcons.micOff : AppIcons.mic),
            size: 12,
            color: muted == true ? tokens.textSecondary : tokens.accent,
          ),
          const SizedBox(width: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: tokens.textPrimary),
          ),
        ],
      ),
    );
  }
}
