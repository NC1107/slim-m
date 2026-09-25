// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The in-call surface: one stage for whatever deserves the room, and
/// everything else small and reachable below it.
///
/// Before this, a screen share, a local camera preview and the roster each
/// painted their own full-width box inside one scrolling column - reported
/// directly by the owner: "it creates 3 different boxes... not very easy to
/// navigate on mobile or vertical views." Nothing here answers "what is a
/// participant" with more than two visual surfaces: their own camera-or-
/// avatar tile, which they always have, in [_ParticipantGrid] or the
/// [_Filmstrip]; and, only while they are actually sharing, the one
/// screen-share tile that becomes [_StageWithFilmstrip]'s stage. The local
/// participant's camera renders inside their own tile exactly like everyone
/// else's now - there is no second, enlarged self-preview box any more.
///
/// The stage is automatic and narrow on purpose: a live share always wins
/// it, and absent one there is no stage at all, just the grid every call
/// already showed. Chasing "whoever is currently speaking" onto the stage
/// was considered and dropped - it needs a debounce to avoid flickering
/// between speakers, real complexity this pass has no measured need for, and
/// it is not what Discord itself does by default either. An explicit tap-
/// to-pin affordance was also considered and dropped for now: the same tap a
/// tile would need for "pin to stage" is the tap [CallParticipantTile]
/// already spends on opening a participant's profile (the only route to
/// per-participant volume outside the member pane), and a touch-only device
/// has no secondary-click to fall back on the way a desktop pointer does.
/// Resolving that gesture conflict is a real UX decision, not a coin flip,
/// and it is named as a follow-up rather than guessed at here.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';
import 'call_participant_tiles.dart';
import 'call_roster_motion.dart';
import 'fullscreen_video_overlay.dart';
import 'local_screen_share_banner.dart';
import 'screen_share_stage.dart';

/// The dock's own visible height plus its margin, so the last row of
/// content reserves room rather than have the floating card cover it.
const double _dockClearance = 76;

/// Tall enough for [CallParticipantTile]'s own content (a camera tile runs
/// to about 110) with room to centre it, short enough that the stage above
/// still gets most of the height on a phone in portrait.
const double _filmstripHeight = 128;

/// The whole in-call body: a compact header, a stage when one is warranted,
/// and either a horizontal filmstrip (stage present) or a wrapping grid
/// (nobody sharing) of every participant's own tile.
class CallStageLayout extends StatelessWidget {
  const CallStageLayout({
    super.key,
    required this.voice,
    required this.controller,
    required this.onOpenProfile,
    required this.isDm,
    this.menuItemsBuilder,
  });

  final VoiceState voice;
  final VoiceController controller;

  /// [BuildContext] is the tapped tile's own - the anchor a popover opened
  /// from it has to hang off, not the screen's outer context every tile
  /// shares. Passing the wrong one pins the popover wherever that outer
  /// context happens to render instead of beside the tile that was tapped.
  final void Function(BuildContext anchor, VoiceParticipant participant)
  onOpenProfile;

  /// Needed only for the alone-in-call hint's canvas mention below.
  final bool isDm;

  /// A tile's own right-click/long-press quick-actions rows, bound to the
  /// participant [participantTile] builds each tile for -
  /// `participant_call_menu.dart`'s own `participantCallMenuItems`, shared
  /// with the canvas bubble's own context menu.
  final List<Widget> Function(
    BuildContext context,
    VoiceParticipant participant,
    VoidCallback close,
  )?
  menuItemsBuilder;

  @override
  Widget build(BuildContext context) {
    final sharer = stageSharer(voice.participants);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16 + _dockClearance,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CallHeader(voice: voice),
          // Withheld once the mirrored stage tile already says the same thing via its own caption.
          if (voice.screenSharing && sharer?.isLocal != true)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.s12),
              child: LocalScreenShareBanner(),
            )
          else if (voice.awaitingBroadcast)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.s12),
              child: LocalScreenSharePendingBanner(),
            ),
          if (voice.error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: AppErrorState(message: voice.error!),
            ),
          const SizedBox(height: AppSpacing.s12),
          Expanded(
            child: AppFadeIn(
              // Keyed on whether a stage exists, not who is sharing: a hand-off between sharers must not re-fade the whole filmstrip.
              key: ValueKey(sharer != null ? 'stage' : 'grid'),
              child: sharer != null
                  ? _StageWithFilmstrip(
                      sharer: sharer,
                      participants: voice.participants,
                      controller: controller,
                      onOpenProfile: onOpenProfile,
                      menuItemsBuilder: menuItemsBuilder,
                    )
                  : _ParticipantGrid(
                      participants: voice.participants,
                      controller: controller,
                      onOpenProfile: onOpenProfile,
                      isDm: isDm,
                      menuItemsBuilder: menuItemsBuilder,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The participant whose screen takes the stage: a remote sharer if any is
/// live, or your own if you are the only one - unlike an earlier version
/// that excluded the local participant outright and so never showed a
/// share to somebody sharing alone.
VoiceParticipant? stageSharer(List<VoiceParticipant> participants) {
  VoiceParticipant? own;
  for (final p in participants) {
    if (!p.isScreenSharing) continue;
    if (!p.isLocal) return p;
    own = p;
  }
  return own;
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({required this.voice});

  final VoiceState voice;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final style = AppText.caption.copyWith(color: tokens.textSecondary);
    return Row(
      children: [
        Text('${voice.participants.length} in call', style: style),
        if (voice.connectedAt != null) ...[
          Text(' · ', style: style),
          CallDuration(since: voice.connectedAt!),
        ],
      ],
    );
  }
}

/// The share stage, fixed and always visible, above a horizontal strip of
/// every participant's own small tile - including the sharer's, since their
/// camera (or lack of one) is separate from the screen they are sharing.
class _StageWithFilmstrip extends StatelessWidget {
  const _StageWithFilmstrip({
    required this.sharer,
    required this.participants,
    required this.controller,
    required this.onOpenProfile,
    this.menuItemsBuilder,
  });

  final VoiceParticipant sharer;
  final List<VoiceParticipant> participants;
  final VoiceController controller;
  final void Function(BuildContext anchor, VoiceParticipant participant)
  onOpenProfile;
  final List<Widget> Function(BuildContext, VoiceParticipant, VoidCallback)?
  menuItemsBuilder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ScreenShareStage(
          sharerName: sharer.name,
          isLocal: sharer.isLocal,
          onExpand: () => showFullscreenVideo(
            context,
            identity: sharer.identity,
            label: sharer.isLocal ? 'Your screen' : "${sharer.name}'s screen",
            kind: FullscreenVideoKind.screenShare,
          ),
          child: controller.screenShareViewFor(sharer.identity),
        ),
      ),
      const SizedBox(height: AppSpacing.s12),
      SizedBox(
        height: _filmstripHeight,
        child: _Filmstrip(
          participants: participants,
          controller: controller,
          onOpenProfile: onOpenProfile,
          menuItemsBuilder: menuItemsBuilder,
        ),
      ),
    ],
  );
}

/// Enter-only motion: a joiner's tile pops in, while a leaver here reflows
/// at once, since a separated horizontal strip has no in-place slot for an
/// exit the way [AnimatedRosterWrap]'s grid does.
class _Filmstrip extends StatelessWidget {
  const _Filmstrip({
    required this.participants,
    required this.controller,
    required this.onOpenProfile,
    this.menuItemsBuilder,
  });

  final List<VoiceParticipant> participants;
  final VoiceController controller;
  final void Function(BuildContext anchor, VoiceParticipant participant)
  onOpenProfile;
  final List<Widget> Function(BuildContext, VoiceParticipant, VoidCallback)?
  menuItemsBuilder;

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: participants.length,
    separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.s12),
    itemBuilder: (context, index) {
      final participant = participants[index];
      return Center(
        // Keyed at the item root so a roster shift never replays the pop.
        key: ValueKey('film-${participant.identity}'),
        child: CallTilePop(
          child: participantTile(
            context,
            participant,
            controller,
            onOpenProfile,
            menuItemsBuilder: menuItemsBuilder,
          ),
        ),
      );
    },
  );
}

/// Every participant, wrapped and centred like a call rather than listed -
/// the layout every call without a share already had, just without a second
/// box for the local camera on top of it.
class _ParticipantGrid extends StatelessWidget {
  const _ParticipantGrid({
    required this.participants,
    required this.controller,
    required this.onOpenProfile,
    required this.isDm,
    this.menuItemsBuilder,
  });

  final List<VoiceParticipant> participants;
  final VoiceController controller;
  final void Function(BuildContext anchor, VoiceParticipant participant)
  onOpenProfile;
  final bool isDm;
  final List<Widget> Function(BuildContext, VoiceParticipant, VoidCallback)?
  menuItemsBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Bounded to the same width the wrap itself is capped to below, so the tile size matches what actually fits rather than the wider unbounded pane.
      final tileWidth = callGridTileWidth(
        constraints.copyWith(
          maxWidth: constraints.maxWidth.clamp(0, kContentColumnMax),
        ),
        participants.length,
      );
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            // Capped like a settings column: a 1:1 call was two small tiles adrift in a full-bleed void, and a bounded room reads as designed.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentColumnMax),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRosterWrap(
                    participants: participants,
                    spacing: AppSpacing.s16,
                    runSpacing: AppSpacing.s16,
                    tileFor: (context, p) => participantTile(
                      context,
                      p,
                      controller,
                      onOpenProfile,
                      width: tileWidth,
                      menuItemsBuilder: menuItemsBuilder,
                    ),
                  ),
                  if (participants.length == 1) ...[
                    const SizedBox(height: AppSpacing.s24),
                    _AloneHint(isDm: isDm),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Shown only while nobody else has joined and nobody is sharing: a calm
/// wait, not a scary empty room, plus a pointer toward the canvas toggle
/// already in `VoiceCallDock` - a plain hint, not a second interactive
/// button, so a solo caller never sees two controls that both open the same
/// canvas. A DM call already names its own canvas button on `_DmCallBar` at
/// every width, so the hint here is scoped to a real voice channel.
class _AloneHint extends StatelessWidget {
  const _AloneHint({required this.isDm});

  final bool isDm;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Waiting for others to join.',
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        if (!isDm) ...[
          const SizedBox(height: AppSpacing.s8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                AppIcons.canvas,
                size: AppSizes.icon16,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s4),
              Flexible(
                child: Text(
                  'Open the canvas below while you wait',
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One participant's tile, shared by the grid and the filmstrip: their live
/// camera when it is on (local participants included, now that there is no
/// separate enlarged self-preview to show it instead), their avatar
/// otherwise, and a way to open either full screen.
Widget participantTile(
  BuildContext context,
  VoiceParticipant participant,
  VoiceController controller,
  void Function(BuildContext anchor, VoiceParticipant participant)
  onOpenProfile, {
  double width = kCallTileMinWidth,
  List<Widget> Function(BuildContext, VoiceParticipant, VoidCallback)?
  menuItemsBuilder,
}) {
  final showsCamera = participant.isCameraOn;
  return CallParticipantTile(
    participant: participant,
    width: width,
    // CallParticipantTile hands back its own context here - see its own doc.
    onTap: (anchor) => onOpenProfile(anchor, participant),
    cameraView: showsCamera
        ? controller.cameraViewFor(participant.identity)
        : null,
    onExpand: showsCamera
        ? () => showFullscreenVideo(
            context,
            identity: participant.identity,
            label: participant.isLocal ? 'Your camera' : participant.name,
            kind: FullscreenVideoKind.camera,
          )
        : null,
    contextMenuItemsBuilder: menuItemsBuilder == null
        ? null
        : (menuContext, close) =>
              menuItemsBuilder(menuContext, participant, close),
  );
}
