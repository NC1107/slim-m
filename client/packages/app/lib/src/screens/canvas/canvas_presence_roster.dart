// SPDX-License-Identifier: Apache-2.0
/// Who is here, drawn as a small face-pile rather than left implicit.
///
/// The owner's third report: "the voice canvas feels like its missing life
/// from it." Reading that literally rather than reaching for decoration -
/// this canvas already has real presence machinery (live cursors, in-flight
/// stroke previews, camera bubbles), and almost none of it is visible while
/// the board is quiet: a cursor only exists while somebody is moving a
/// pointer, and a camera bubble only exists while somebody's camera is on.
/// Between those two moments - which is most of a real conversation - a
/// shared canvas with people actually on it reads identically to an empty
/// one nobody has ever opened.
///
/// This closes that gap honestly rather than by inventing a signal the wire
/// does not carry. There is no "has this canvas open" event from the server
/// (see this file's own knowledge-base entry for why one would need a real
/// server change, left for the owner rather than faked here) - only two
/// things a client already knows for certain: who is on this channel's call,
/// and whose cursor has moved recently enough that [CanvasCursors] has not
/// pruned it. Both are real, both are already flowing through this pane, and
/// their union is exactly "who this canvas can currently prove is present."
/// A quiet call with nobody drawing renders nothing here, which is the
/// honest answer, not a bug this widget should paper over.
///
/// Membership changes swap instantly, deliberately not cross-faded: a new
/// face appearing already carries the meaning on its own, and animating the
/// swap on top of that would be motion for its own sake rather than motion
/// that says anything a plain appearance does not already say.
///
/// **A known boundary, not a bug: somebody with the canvas open but neither
/// on the call nor moving a pointer is invisible here.** Silently reading a
/// shared board is a real, common thing to do, and there is genuinely no
/// wire signal for it - "has this canvas open" is not an event the server
/// sends, and inventing one client-side would be exactly the fabrication
/// this file's own opening paragraph already rejected. So a quiet reader
/// reads as absent, the same honest gap a cursor-only or call-only signal
/// always had; closing it needs a real server change, left for the owner.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../widgets/user_avatar.dart';

/// One entry in the face-pile: a name, an id to key the avatar's colour and
/// its animation identity, and a stable sort key.
class _Present {
  const _Present({required this.id, required this.name});

  final String id;
  final String name;
}

/// Positioned top-right by default - the error/truncation banners already
/// claim the top-left-to-center band, and the floating dock owns the bottom.
/// [IgnorePointer]-wrapped throughout, the same treatment `CanvasPresenceLayer`
/// already gives camera bubbles: this is presence chrome, never a drawing
/// target.
///
/// **There is no tie-break against the self camera bubble any more.**
/// Before decision 0010's media-tile work the self bubble was a
/// screen-anchored overlay with its own resting corner, and this class used
/// to watch it and swap to top-left when the two would collide. The self
/// bubble is a world-anchored, freely draggable tile now, like every other
/// camera or screen-share tile, so it has no screen corner of its own left
/// to collide with - [alignment] is unused with any value but the default
/// today. What a world-anchored tile *can* still do is pan underneath this
/// fixed corner, controls included; that residual is recorded, not solved,
/// in decision 0010's own "What was left" section.
class CanvasPresenceRoster extends StatefulWidget {
  const CanvasPresenceRoster({
    super.key,
    required this.callParticipants,
    this.cursors,
    this.alignment = Alignment.topRight,
  });

  /// Already filtered for blocking by the caller - `_callParticipants()`
  /// for this, `CanvasCursorRelay.applyRemote` for [cursors] - the same
  /// upstream-filtering shape every other presence surface on this canvas
  /// already follows, so this widget has nothing left to filter itself.
  final List<VoiceParticipant> callParticipants;
  final CanvasCursors? cursors;

  /// See this class's own doc for why this is ever anything but the
  /// default top-right.
  final Alignment alignment;

  @override
  State<CanvasPresenceRoster> createState() => _CanvasPresenceRosterState();
}

class _CanvasPresenceRosterState extends State<CanvasPresenceRoster> {
  @override
  void initState() {
    super.initState();
    widget.cursors?.addListener(_onCursorsChanged);
  }

  @override
  void didUpdateWidget(covariant CanvasPresenceRoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cursors != widget.cursors) {
      oldWidget.cursors?.removeListener(_onCursorsChanged);
      widget.cursors?.addListener(_onCursorsChanged);
    }
  }

  @override
  void dispose() {
    widget.cursors?.removeListener(_onCursorsChanged);
    super.dispose();
  }

  void _onCursorsChanged() {
    if (mounted) setState(() {});
  }

  List<_Present> _present() {
    final byId = <String, _Present>{};
    for (final p in widget.callParticipants) {
      if (p.isLocal) continue;
      byId[p.identity] = _Present(id: p.identity, name: p.name);
    }
    for (final cursor in widget.cursors?.all ?? const <CanvasCursor>[]) {
      byId.putIfAbsent(
        cursor.id,
        () => _Present(id: cursor.id, name: cursor.label),
      );
    }
    final present = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return present;
  }

  @override
  Widget build(BuildContext context) {
    final present = _present();
    return Align(
      alignment: widget.alignment,
      child: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.s12),
        child: IgnorePointer(
          child: present.isEmpty
              ? const SizedBox.shrink()
              : _FacePile(present: present),
        ),
      ),
    );
  }
}

class _FacePile extends StatelessWidget {
  const _FacePile({required this.present});

  final List<_Present> present;

  static const int _maxShown = 4;
  static const double _avatarSize = 24;
  static const double _overlap = 8;

  /// The horizontal distance from one avatar's left edge to the next -
  /// [_avatarSize] minus how much the next one overlaps this one.
  static const double _stride = _avatarSize - _overlap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final shown = present.take(_maxShown).toList();
    final overflow = present.length - shown.length;
    // Positioned in an explicit Stack, not negative Padding, which asserts non-negative.
    final stackWidth = shown.isEmpty
        ? 0.0
        : _avatarSize + (shown.length - 1) * _stride;
    return Semantics(
      container: true,
      label: 'On this canvas: ${present.map((p) => p.name).join(', ')}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadii.full),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: stackWidth,
                height: _avatarSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * _stride,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: tokens.surfaceRaised,
                              width: 2,
                            ),
                          ),
                          child: AuthorAvatar(
                            name: shown[i].name,
                            userId: shown[i].id,
                            size: _avatarSize,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (overflow > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                  ),
                  child: Text(
                    '+$overflow',
                    style: AppText.caption.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: AppWeights.medium,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
