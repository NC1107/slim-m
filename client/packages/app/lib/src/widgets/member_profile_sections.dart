// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The sections a member profile composes from, split out of
/// `member_profile.dart` when the moderation half took that file past the
/// review budget.
///
/// Each is a whole section or nothing. That is the design's own rule: a
/// section you have no rights or context for is *absent*, never
/// present-and-disabled, which is what keeps a plain member's profile to two
/// verbs instead of a wall of greyed rows.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';
import 'user_avatar.dart';

/// Avatar, name, role badge, and the presence word beside its dot - never the
/// dot alone, which is the rule every surface in this app follows.
class MemberProfileHeader extends StatelessWidget {
  const MemberProfileHeader({
    super.key,
    required this.profile,
    required this.status,
    required this.isSelf,
    required this.inCallTogether,
    this.callChannelName,
  });

  final api.UserProfile profile;
  final AppPresence status;
  final bool isSelf;
  final bool inCallTogether;

  /// Refines the shared-call line to name the room. Absent where the caller
  /// does not have the name to hand - the voice screen reads its channel from
  /// a database stream rather than holding it - and then the line reads "in
  /// this call with you", which is unambiguous from inside the call anyway.
  final String? callChannelName;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final badge = profile.roles.isEmpty ? null : profile.roles.first;
    final timedOut = profile.timedOutUntil != null;

    final subtitle = inCallTogether
        ? Row(
            children: [
              Icon(AppIcons.speaker, size: 12, color: tokens.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  callChannelName == null
                      ? 'in this call with you'
                      : 'in $callChannelName with you',
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: tokens.accent),
                ),
              ),
            ],
          )
        : Row(
            children: [
              AppStatusDot(status: status),
              const SizedBox(width: AppSpacing.s8),
              Flexible(
                child: Text(
                  isSelf
                      ? '${presenceWord(status)} - you'
                      : presenceWord(status),
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        children: [
          // The avatar only, never the text, which would cost its contrast.
          Opacity(
            opacity: timedOut ? 0.7 : 1,
            child: UserAvatar(
              userId: profile.id,
              avatarUpdatedAt: profile.avatarUpdatedAt,
              name: profile.displayName,
              size: 44,
              // The ring here means "in a call with you", so the name says that.
              speaking: inCallTogether,
              semanticLabel: inCallTogether
                  ? '${profile.displayName}, in a call with you'
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: AppWeights.semi,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: AppSpacing.s8),
                      AppBadge(variant: AppBadgeVariant.role, label: badge),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                subtitle,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String presenceWord(AppPresence status) => switch (status) {
  AppPresence.online => 'online',
  AppPresence.away => 'away',
  AppPresence.dnd => 'do not disturb',
  AppPresence.offline => 'offline',
  AppPresence.hidden => 'appearing offline',
};

/// The timed-out banner: amber rather than red, because it expires on its own
/// and the error grammar reserves red for something that needs acting on.
///
/// Says exactly what is restricted rather than only that something is, and
/// offers "Lift" only to somebody who can actually lift it. A member without
/// that right still sees the badge: why they cannot hear from someone is
/// information they are entitled to.
class MemberTimeoutBadge extends StatelessWidget {
  const MemberTimeoutBadge({super.key, required this.until, this.onLift});

  /// Unix milliseconds.
  final int until;
  final VoidCallback? onLift;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final remaining = DateTime.fromMillisecondsSinceEpoch(
      until,
    ).difference(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        0,
        AppSpacing.s12,
        AppSpacing.s12,
      ),
      child: AppCallout(
        icon: AppIcons.clock,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Timed out - '),
                        TextSpan(
                          text: formatRemaining(remaining),
                          style: AppText.code.copyWith(
                            color: tokens.warnText,
                            fontSize: 12,
                          ),
                        ),
                        const TextSpan(text: ' remaining'),
                      ],
                    ),
                    style: AppText.caption.copyWith(color: tokens.warnText),
                  ),
                  Text(
                    'Can read messages and view the canvas; '
                    "can't draw, send messages, or join voice.",
                    style: AppText.caption.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onLift != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.s8),
                child: AppButton(
                  label: 'Lift',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: onLift,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How long is left, in the coarsest unit that is still true.
///
/// Coarse on purpose: a timeout is not a countdown anybody should watch, and
/// a badge re-rendering a ticking second would be movement with no meaning.
String formatRemaining(Duration remaining) {
  if (remaining.isNegative) return 'moments';
  if (remaining.inHours >= 24) return '${remaining.inDays}d';
  if (remaining.inMinutes >= 60) return '${remaining.inHours}h';
  if (remaining.inMinutes >= 1) return '${remaining.inMinutes}m';
  return '${remaining.inSeconds}s';
}

/// What this listener can do about hearing one participant, all of it local.
///
/// The volume slider is present only where the platform can actually change
/// gain: on Linux, Windows and web the underlying call either throws or
/// quietly does nothing (see `audio_gain.dart` in the rtc package), and a
/// control that does nothing between its ends is worse than no control. The
/// mute half works everywhere, so it always shows.
class MemberLocalAudioSection extends StatefulWidget {
  const MemberLocalAudioSection({
    super.key,
    required this.identity,
    required this.controller,
  });

  final String identity;
  final VoiceController controller;

  @override
  State<MemberLocalAudioSection> createState() =>
      _MemberLocalAudioSectionState();
}

class _MemberLocalAudioSectionState extends State<MemberLocalAudioSection> {
  /// The slider owns its position while it is being dragged. Reading it back
  /// from the session on every frame would make the drag depend on a round
  /// trip through the platform channel.
  late double _volume = widget.controller.volumeFor(widget.identity);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final muted = widget.controller.isLocallyMuted(widget.identity);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.controller.supportsParticipantVolume)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s8,
              AppSpacing.s12,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Volume for you',
                      style: AppText.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    Text(
                      '${(_volume * 100).round()}%',
                      style: AppText.code.copyWith(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                AppSlider(
                  value: _volume * 100,
                  min: 0,
                  max: kMaxParticipantVolume * 100,
                  ticks: const ['0', '100', '200'],
                  semanticLabel: 'Volume for you',
                  muted: muted,
                  onChanged: (next) {
                    setState(() => _volume = next / 100);
                    widget.controller.setVolumeFor(widget.identity, _volume);
                  },
                ),
              ],
            ),
          ),
        AppMenuItem(
          label: muted ? 'Unmute for me' : 'Mute for me',
          leading: muted ? AppIcons.speakerOff : AppIcons.speaker,
          selected: muted,
          onTap: () async {
            await widget.controller.setLocallyMuted(widget.identity, !muted);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}

/// The inline timeout durations from the design: one tap, no dialog.
///
/// A dialog for "5 minutes" would be a confirmation step for something that
/// undoes itself, and the undo lives on the resulting badge rather than in a
/// toast that floats away.
///
/// Two separate defects made this unreadable in the member pane, which at
/// 236px is the narrowest surface it appears on. Both showed in one
/// screenshot, as two of the four durations rendering as empty boxes.
///
/// The buttons were four [Expanded] in a [Row]. Expanded makes each child's
/// width the row's decision rather than the label's, so at that width every
/// button was narrower than its own padding plus text and every label was
/// clipped to a fixed 16px - measured, and identical for `5m` and `24h` alike.
/// No overflow was reported for this, because Expanded forces the fit. A
/// [Wrap] lets each take the width it needs and fall to a second line when
/// there isn't any; a wider profile sheet still fits them on one.
///
/// Separately, the header's [Text] sat in a [Row] with no [Flexible], so that
/// row wanted 46px more than the pane had and reported a real overflow. That
/// one is independent of the buttons and shows at this width alone.
///
/// `timeout_chips_width_test.dart` pins both: nothing overflows, and a
/// three-character label stays wider than a two-character one.
class TimeoutDurationChips extends StatelessWidget {
  const TimeoutDurationChips({super.key, required this.onChosen});

  final void Function(Duration) onChosen;

  static const _options = <(String, Duration)>[
    ('5m', Duration(minutes: 5)),
    ('1h', Duration(hours: 1)),
    ('24h', Duration(hours: 24)),
    ('7d', Duration(days: 7)),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.clock,
                size: AppSizes.icon16,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s8),
              // Flexible, or this runs 46px past the member pane; see the class doc.
              Flexible(
                child: Text(
                  'Time out for...',
                  style: AppText.ui.copyWith(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final (label, duration) in _options)
                AppButton(
                  label: label,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  semanticLabel: 'Time out for $label',
                  onPressed: () => onChosen(duration),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
