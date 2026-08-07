// SPDX-License-Identifier: Apache-2.0
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
  });

  final VoiceState voice;
  final VoiceController controller;
  final ValueChanged<VoiceParticipant> onOpenProfile;

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
          // Pinned above the stage: a per-row glyph is too easy to scroll past.
          if (voice.screenSharing)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.s12),
              child: LocalScreenShareBanner(),
            ),
          if (voice.error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: AppErrorState(message: voice.error!),
            ),
          const SizedBox(height: AppSpacing.s12),
          Expanded(
            child: AppFadeIn(
              key: ValueKey('call-stage-${sharer?.identity ?? 'grid'}'),
              child: sharer != null
                  ? _StageWithFilmstrip(
                      sharer: sharer,
                      participants: voice.participants,
                      controller: controller,
                      onOpenProfile: onOpenProfile,
                    )
                  : _ParticipantGrid(
                      participants: voice.participants,
                      controller: controller,
                      onOpenProfile: onOpenProfile,
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
    final style = TextStyle(color: tokens.textSecondary, fontSize: 12);
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
  });

  final VoiceParticipant sharer;
  final List<VoiceParticipant> participants;
  final VoiceController controller;
  final ValueChanged<VoiceParticipant> onOpenProfile;

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
        ),
      ),
    ],
  );
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({
    required this.participants,
    required this.controller,
    required this.onOpenProfile,
  });

  final List<VoiceParticipant> participants;
  final VoiceController controller;
  final ValueChanged<VoiceParticipant> onOpenProfile;

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: participants.length,
    separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.s12),
    itemBuilder: (context, index) => Center(
      child: participantTile(
        context,
        participants[index],
        controller,
        onOpenProfile,
      ),
    ),
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
  });

  final List<VoiceParticipant> participants;
  final VoiceController controller;
  final ValueChanged<VoiceParticipant> onOpenProfile;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.s16,
            runSpacing: AppSpacing.s16,
            children: [
              for (final p in participants)
                participantTile(context, p, controller, onOpenProfile),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One participant's tile, shared by the grid and the filmstrip: their live
/// camera when it is on (local participants included, now that there is no
/// separate enlarged self-preview to show it instead), their avatar
/// otherwise, and a way to open either full screen.
Widget participantTile(
  BuildContext context,
  VoiceParticipant participant,
  VoiceController controller,
  ValueChanged<VoiceParticipant> onOpenProfile,
) {
  final showsCamera = participant.isCameraOn;
  return CallParticipantTile(
    participant: participant,
    onTap: () => onOpenProfile(participant),
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
  );
}
