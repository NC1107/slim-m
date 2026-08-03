// SPDX-License-Identifier: Apache-2.0
/// The in-call participant tiles, and the call-duration readout.
///
/// A call used to render as a top-anchored list of small rows over a mostly
/// empty pane, which read as a debug view rather than a place people are.
/// With nobody sharing a screen, participants now sit as centred tiles sized
/// for the two-to-eight-person calls this product is for; the compact rows
/// remain for under a share stage, where vertical room is spoken for.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import 'user_avatar.dart';

/// One participant as a tile: a large avatar with the speaking ring, the
/// name beneath, and the mute or share state as a small badge.
class CallParticipantTile extends StatelessWidget {
  const CallParticipantTile({super.key, required this.participant, this.onTap});

  final VoiceParticipant participant;

  /// Opens this participant's profile. The only route to per-participant
  /// volume that does not go through the member pane, which is the wrong
  /// place to look for it while you are staring at the person talking.
  final VoidCallback? onTap;

  String get _semanticLabel {
    final parts = <String>[
      participant.isLocal ? '${participant.name}, you' : participant.name,
      participant.isMuted ? 'muted' : 'microphone on',
      if (participant.isSpeaking) 'speaking',
      if (participant.isScreenSharing) 'sharing their screen',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      container: true,
      label: _semanticLabel,
      button: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          // Right-click reaches the same profile a tap already opens.
          onSecondaryTapDown: onTap == null ? null : (_) => onTap!(),
          child: SizedBox(
            width: 112,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AuthorAvatar(
                      name: participant.name,
                      userId: participant.identity,
                      size: 64,
                      speaking: participant.isSpeaking,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.surfaceRaised,
                          shape: BoxShape.circle,
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Icon(
                          participant.isScreenSharing
                              ? AppIcons.screenShare
                              : participant.isMuted
                              ? AppIcons.micOff
                              : AppIcons.mic,
                          size: 12,
                          color: participant.isMuted
                              ? tokens.textSecondary
                              : tokens.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  participant.isLocal
                      ? '${participant.name} (you)'
                      : participant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppText.ui.copyWith(color: tokens.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `12:34`-style elapsed time since [since], ticking once a second.
///
/// A text update, not motion, so it does not route through reduce-motion;
/// the timer only exists while the readout is mounted.
class CallDuration extends StatefulWidget {
  const CallDuration({super.key, required this.since});

  final DateTime since;

  @override
  State<CallDuration> createState() => _CallDurationState();
}

class _CallDurationState extends State<CallDuration> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _format(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final elapsed = DateTime.now().difference(widget.since);
    return Text(
      _format(elapsed.isNegative ? Duration.zero : elapsed),
      style: AppText.caption.copyWith(
        color: tokens.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
