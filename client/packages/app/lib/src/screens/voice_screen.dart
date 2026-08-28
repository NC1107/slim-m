// SPDX-License-Identifier: Apache-2.0
/// A voice channel: joining, and the call once you are in it.
///
/// Clicking a voice channel joins it directly. There used to be a lobby
/// screen with a mic/camera pre-toggle and an explicit Join button; the
/// owner asked twice for it to be gone, so a channel arrival auto-joins
/// (`_VoiceScreenState._maybeAutoJoin`) rather than waiting on a tap. The mic
/// and camera still open however `VoiceState.microphoneEnabled` /
/// `cameraEnabled` were last left (see `voice_controller.dart`'s `leave`,
/// which now carries those two fields across the reset), so muting before
/// leaving still means the next join opens muted.
///
/// The one case that still needs an explicit decision is switching calls:
/// arriving at a different voice channel while already connected elsewhere
/// shows `VoiceSwitchPrompt` instead of silently hanging up the first call.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/call_recap.dart';
import '../providers/member_presence.dart' show membersProvider, presenceOf;
import '../providers/presence_controller.dart';
import '../providers/voice_controller.dart';
import '../providers/voice_flags.dart';
import '../widgets/call_stage_layout.dart';
import '../widgets/member_profile.dart';
import 'voice_call_dock.dart';
import 'voice_join_preview.dart';

/// Whether [voice] describes a live call somewhere other than [channelId]:
/// the one case an arrival still has to ask about before joining.
///
/// `voice.joining` covers the window a join has already claimed
/// [VoiceState.channelId] but has not yet moved [VoiceState.state] off
/// whatever it was before (the token round trip in
/// [VoiceController.join] carries no state transition of its own) - without
/// it, an arrival during that window read the controller as idle and
/// auto-joined a second call with no [VoiceSwitchPrompt] at all.
///
/// Takes [VoiceFlags]: the roster has nothing to say about whether another
/// channel's call is already busy.
bool _busyElsewhere(VoiceFlags voice, String channelId) =>
    voice.channelId != null &&
    voice.channelId != channelId &&
    (voice.state == VoiceSessionState.connected ||
        voice.state == VoiceSessionState.connecting ||
        voice.joining);

/// [voice]'s recap, but only when it belongs to [channelId]: `VoiceController`
/// is one instance for every channel, and CLAUDE.md already recorded this
/// exact leak shape once for an in-call error message shown in the wrong
/// channel's preview.
CallRecap? recapForChannel(VoiceFlags voice, String channelId) =>
    voice.recap?.channelId == channelId ? voice.recap : null;

class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({required this.channelId, this.isDm = false, super.key});

  final String channelId;

  /// Whether this is a DM's call rather than a real voice channel's, so the
  /// rejoin screen can say "Call" instead of "Voice channel".
  final bool isDm;

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  /// The channel id an automatic join has already been requested for, so a
  /// failure - or an explicit hang-up, which leaves this same screen still
  /// mounted - does not retry itself on every rebuild. Cleared only when
  /// [widget]'s own channel changes, which is what makes revisiting the same
  /// channel a fresh attempt again.
  String? _autoJoinedFor;

  @override
  void didUpdateWidget(covariant VoiceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) _autoJoinedFor = null;
  }

  void _maybeAutoJoin(VoiceController controller) {
    if (_autoJoinedFor == widget.channelId) return;
    _autoJoinedFor = widget.channelId;
    final channelId = widget.channelId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.join(channelId);
    });
  }

  /// The switch prompt's own confirm action: marked as attempted the same
  /// way an automatic join is, so a failure lands on the rejoin screen
  /// rather than looping back into another switch prompt.
  void _switchNow(VoiceController controller) {
    _autoJoinedFor = widget.channelId;
    controller.join(widget.channelId);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = ref.watch(voiceFlagsProvider);
    final controller = ref.read(voiceControllerProvider.notifier);
    final channelId = widget.channelId;
    final inThisChannel = voice.channelId == channelId;
    final connectedHere =
        inThisChannel && voice.state == VoiceSessionState.connected;
    final connectingHere =
        inThisChannel && voice.state == VoiceSessionState.connecting;
    // Without this, `join`'s own in-flight window (see its own comment) reads as `attemptedThis` and briefly flashes the rejoin screen.
    final joiningHere = inThisChannel && voice.joining;
    final busyElsewhere = _busyElsewhere(voice, channelId);
    // The same canvas-pane remount that connectedHere guards against also
    // wipes this memory when the user hung up *before* closing the canvas:
    // `leave()` nulls `voice.channelId`, so the remounted screen cannot read
    // connectedHere at all. `justLeftChannelId` is what survives that instead
    // - see VoiceState.rejoinGuardWindow for how long it is trusted.
    final justLeftThis =
        voice.justLeftChannelId == channelId &&
        voice.justLeftAt != null &&
        DateTime.now().difference(voice.justLeftAt!) <
            VoiceState.rejoinGuardWindow;
    // Mounting already connected is not a fresh arrival, and this screen is
    // remounted with an empty [_autoJoinedFor] every time the canvas pane
    // swaps in and back out - without this, hanging up after that round trip
    // reads as an arrival and auto-joins the call straight back. Latching
    // justLeftThis in here too means a widget that stays mounted past
    // VoiceState.rejoinGuardWindow keeps reading as already attempted,
    // rather than flipping to a fresh arrival once the window lapses under it.
    if (connectedHere || justLeftThis) _autoJoinedFor = channelId;
    final attemptedThis = _autoJoinedFor == channelId;

    // `join` never clears `channelId` on error, so an error only ever belongs here.
    final errorMessage =
        inThisChannel && voice.state == VoiceSessionState.failed
        ? voice.error
        : null;
    final canRetry = errorMessage == null || voice.retryable;

    final stage = connectedHere
        ? 'call'
        : (connectingHere || joiningHere)
        ? 'connecting'
        : busyElsewhere
        ? 'switch'
        : attemptedThis
        ? 'left'
        : 'joining';

    if (stage == 'joining') _maybeAutoJoin(controller);

    return Container(
      color: tokens.surfaceBase,
      child: AppFadeIn(
        // 'joining' reads as 'connecting' here, so a fresh arrival never fades through a stage nobody would see.
        key: ValueKey('voice-${stage == 'joining' ? 'connecting' : stage}'),
        child: switch (stage) {
          'call' => _InCall(channelId: channelId, isDm: widget.isDm),
          'connecting' || 'joining' => const VoiceConnecting(),
          'switch' => VoiceSwitchPrompt(onSwitch: () => _switchNow(controller)),
          _ => VoiceRejoinScreen(
            channelId: channelId,
            isDm: widget.isDm,
            errorMessage: errorMessage,
            canRetry: canRetry,
            onRetry: () => controller.join(channelId),
            recap: recapForChannel(voice, channelId),
          ),
        },
      ),
    );
  }
}

/// In the call: who is here, and the controls.
///
/// The controls used to trail this column as a full-width anchored strip,
/// which is exactly what made opening the canvas make them disappear
/// outright - `ConversationPane` swaps the whole pane, controls included,
/// rather than merely covering them. They float over this content instead
/// now, in the same `FloatingDockCard` a canvas's own controls use (see
/// `canvas_call_dock.dart`), so a future viewer comparing the two screens
/// sees one dock idea rather than two. What sits beneath them is
/// `CallStageLayout` (`widgets/call_stage_layout.dart`), which carries its
/// own bottom clearance so the floating card never sits on top of its
/// content.
///
/// [isDm] withholds the dock's own canvas toggle - see `voice_call_dock.dart`
/// for the DM half of why, and `canvas_pane_test.dart` for the header
/// affordance this is in addition to, not a replacement for.
class _InCall extends ConsumerWidget {
  const _InCall({required this.channelId, required this.isDm});

  final String channelId;
  final bool isDm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);

    return Stack(
      children: [
        CallStageLayout(
          voice: voice,
          controller: controller,
          onOpenProfile: (p) => _openProfile(context, ref, p),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.all(AppSpacing.s12),
            // Pure fade: VoiceCallDock owns its own per-call rise now.
            child: AppFadeIn(
              key: ValueKey('call-dock-$channelId'),
              offset: 0,
              child: VoiceCallDock(
                controller: controller,
                voice: VoiceFlags.from(voice),
                canvasChannelId: isDm ? null : channelId,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens a caller's profile from their tile, which is the only route to the
/// per-participant volume control that does not go via the member pane.
///
/// The roster carries an identity and a name, not a profile, so the member
/// list is where the rest comes from. Absent from it (a member past the
/// page cap) means no profile to show rather than a wrong one, so nothing
/// opens - the alternative is a popover whose moderation half is missing
/// with no way to tell that it is.
void _openProfile(
  BuildContext context,
  WidgetRef ref,
  VoiceParticipant participant,
) {
  if (participant.isLocal) return;
  final profile = ref
      .read(membersProvider)
      .valueOrNull
      ?.where((m) => m.id == participant.identity)
      .firstOrNull;
  if (profile == null) return;

  showMemberProfile(
    context,
    ref,
    profile: profile,
    status: presenceOf(ref.read(presenceControllerProvider)[profile.id]),
  );
}
