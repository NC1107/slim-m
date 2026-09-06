// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The in-call participant tiles, and the call-duration readout.
///
/// A call used to render as a top-anchored list of small rows over a mostly
/// empty pane, which read as a debug view rather than a place people are.
/// One tile shape now covers both places a participant can appear -
/// `call_stage_layout.dart`'s centred grid when nobody is sharing, and its
/// horizontal filmstrip beneath the stage when somebody is - but the grid's
/// tiles no longer sit at one fixed size: [callGridTileWidth] grows them for
/// a two-person call and shrinks them back down past eight, so the room
/// this product is built for reads as a room rather than a debug view no
/// matter how many of the two-to-twelve show up. The filmstrip keeps the
/// original fixed size - it is already correct, since a screen share is
/// already holding the room.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../format.dart';
import 'fullscreen_video_overlay.dart';
import 'user_avatar.dart';

/// The tile's size floor: the original fixed width, still right once a call
/// is full enough that more room per tile would not help.
const double kCallTileMinWidth = 112;

/// The tile's size ceiling: past this, more room reads as air around a face
/// rather than a bigger one.
const double kCallTileMaxWidth = 200;

/// The video box's height as a fraction of tile width, matching the
/// original fixed 112x84 box.
const double _kCallTileVideoAspect = 0.75;

/// The name label's own height, plus the gap above it - additive rather
/// than a fraction of width, since neither the label's type nor its gap
/// scale with the tile (`design_system`'s density doc: type does not
/// scale).
const double _kCallTileLabelExtra = 28;

/// How wide one grid tile should render for [count] participants inside
/// [constraints] - the fixed 112px tile made a two-person call look like
/// two small faces in a big empty room; this instead grows tiles to fill
/// the space a small roster leaves, and shrinks them back down once a
/// bigger roster needs the room. Reads window/pane constraints only, never
/// `Platform.isX` - desktop-vs-mobile rule 1, width decides.
///
/// Tries every column count from one tile per row to one row of tiles, and
/// keeps the widest tile that still fits both [constraints] dimensions -
/// the same grid-packing a video call's own tile layout needs elsewhere,
/// cheap here because a call this product is built for never seats more
/// than a handful of people.
double callGridTileWidth(
  BoxConstraints constraints,
  int count, {
  double spacing = AppSpacing.s16,
}) {
  if (count <= 0) return kCallTileMinWidth;
  final maxWidth = constraints.maxWidth.isFinite
      ? constraints.maxWidth
      : kCallTileMaxWidth;
  final maxHeight = constraints.maxHeight;
  var best = kCallTileMinWidth;
  for (var columns = 1; columns <= count; columns++) {
    final rows = (count / columns).ceil();
    var candidate = (maxWidth - (columns - 1) * spacing) / columns;
    if (maxHeight.isFinite) {
      final rowHeight = (maxHeight - (rows - 1) * spacing) / rows;
      final fromHeight =
          (rowHeight - _kCallTileLabelExtra) / _kCallTileVideoAspect;
      if (fromHeight < candidate) candidate = fromHeight;
    }
    if (candidate > best) best = candidate;
  }
  return best.clamp(kCallTileMinWidth, kCallTileMaxWidth);
}

/// One participant as a tile: a large avatar with the speaking ring, the
/// name beneath, and the mute or share state as a small badge - or, once a
/// camera is actually on, the live feed in place of the avatar. [cameraView]
/// is passed for the local participant too now (`call_stage_layout.dart`
/// builds every tile the same way), so there is no separate enlarged
/// self-preview outside this grid any more.
class CallParticipantTile extends StatelessWidget {
  const CallParticipantTile({
    super.key,
    required this.participant,
    this.onTap,
    this.cameraView,
    this.onExpand,
    this.width = kCallTileMinWidth,
  });

  final VoiceParticipant participant;

  /// How wide this tile renders, video box and avatar included - the name
  /// label and mute badge stay their own fixed size regardless. Callers
  /// pass a size fit to the available room; see [callGridTileWidth].
  final double width;

  /// Opens this participant's profile. The only route to per-participant
  /// volume that does not go through the member pane, which is the wrong
  /// place to look for it while you are staring at the person talking.
  final VoidCallback? onTap;

  /// This participant's live camera feed, from
  /// `VoiceController.cameraViewFor` - null whenever there is nothing to show
  /// in its place, so the avatar renders instead.
  final Widget? cameraView;

  /// Opens [cameraView] full screen. Non-null exactly when [cameraView] is,
  /// since there is nothing to expand into otherwise.
  final VoidCallback? onExpand;

  String get _semanticLabel {
    final parts = <String>[
      participant.isLocal ? '${participant.name}, you' : participant.name,
      participant.isMuted ? 'muted' : 'microphone on',
      if (participant.isSpeaking) 'speaking',
      if (participant.isScreenSharing) 'sharing their screen',
    ];
    return parts.join(', ');
  }

  /// A live feed is only worth showing - and expanding - while the flag it
  /// answers for is itself true; a stale `cameraView` handed down the frame
  /// a camera turned off would otherwise still render.
  bool get _showsCamera => cameraView != null && participant.isCameraOn;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final videoHeight = width * _kCallTileVideoAspect;
    // 64 on the original 112px tile - grows with it, never past what a tile this wide has room for.
    final avatarSize = width * 64 / kCallTileMinWidth;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          container: true,
          label: _semanticLabel,
          button: onTap != null,
          onTap: onTap,
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: onTap,
              // Right-click reaches the same profile a tap already opens.
              onSecondaryTapDown: onTap == null ? null : (_) => onTap!(),
              child: AnimatedSize(
                duration: AppMotion.reduced(context, AppMotion.base),
                curve: AppMotion.entrance,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _showsCamera
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.card,
                                  ),
                                  child: SizedBox(
                                    width: width,
                                    height: videoHeight,
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF000000),
                                      ),
                                      child: cameraView,
                                    ),
                                  ),
                                )
                              : AuthorAvatar(
                                  name: participant.name,
                                  userId: participant.identity,
                                  size: avatarSize,
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
          ),
        ),
        if (_showsCamera && onExpand != null)
          Positioned(
            left: 4,
            top: 4,
            child: ExpandVideoButton(
              label: "View ${participant.name}'s camera full screen",
              onTap: onExpand!,
            ),
          ),
      ],
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
    final parts = decomposeDuration(d);
    final m = parts.minutes.toString().padLeft(2, '0');
    final s = parts.seconds.toString().padLeft(2, '0');
    return parts.hours > 0 ? '${parts.hours}:$m:$s' : '$m:$s';
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
