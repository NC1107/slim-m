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

/// One participant's camera tile: their live camera when it is on, or -
/// report 4 in the backlog channel, "if a user is not screen sharing or
/// sharing their camera it should not be a big square, it should just be
/// some sort of representation of them" - their plain avatar with no card
/// around it otherwise. A shrunken video tile was tried first
/// (`presenceCameraOffSize`, still the box this marker sits in for drag and
/// resize purposes) and rejected by the same report: still a box, just a
/// smaller one, where the ask was a different shape of thing entirely.
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
    if (!_showsCamera) {
      return _AvatarMarker(participant: participant);
    }
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return _TileChrome(
      tokens: tokens,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF000000)),
        child: cameraView,
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

/// No card, no border, no shadow, no fixed-colour background: just the
/// avatar this participant already has everywhere else in the app (the
/// member list, a message row), a small muted glyph over its own corner
/// rather than a second badge bar, and their name in plain text underneath.
/// The one thing this still needs from the tile chrome it replaces is a
/// name - unlike a member-list row, a canvas can hold several of these at
/// once with nothing else on screen saying whose avatar is whose.
class _AvatarMarker extends StatelessWidget {
  const _AvatarMarker({required this.participant});

  final VoiceParticipant participant;

  static const double _avatarSize = 56;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(
                name: participant.name,
                userId: participant.identity,
                size: _avatarSize,
                speaking: participant.isSpeaking,
              ),
              if (participant.isMuted)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: tokens.surfaceRaised,
                      shape: BoxShape.circle,
                      border: Border.all(color: tokens.surfaceBase, width: 2),
                    ),
                    child: Icon(
                      AppIcons.micOff,
                      size: 12,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            participant.isLocal
                ? '${participant.name} (you)'
                : participant.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(
              color: tokens.textPrimary,
              shadows: [Shadow(color: tokens.surfaceBase, blurRadius: 4)],
            ),
          ),
        ],
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
