// SPDX-License-Identifier: Apache-2.0
/// The workhorse row: the channel rail, the member list, and every other
/// single-line picker in the app are built from this one widget.
///
/// Ported from the source `ListRow.jsx`: a `position: relative` row with an
/// absolutely-positioned selection marker, `color`/`font-weight` driven by
/// `selected || unread`, and an unread dot that only appears when there is no
/// trailing content to carry that meaning instead.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_haptics.dart';
import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';
import '../../touch_targets.dart';

/// A single-line row: optional leading content, a label, an optional `meta`
/// caption, an optional trailing widget, and four states that combine freely.
///
/// - [selected]: a left accent marker plus a soft accent fill, one of the
///   seven closed accent roles.
/// - [unread]: the source lifts both colour (`text-secondary` to
///   `text-primary`) and weight (regular to medium) for `selected || unread`
///   alike, so unread's *distinguishing* cue from selected is the dot, shown
///   only when [trailing] is absent (a trailing count badge already carries
///   the same meaning, so the dot would be redundant next to it).
/// - [muted]: dims the leading and trailing content to `opacity: 0.62`, but
///   deliberately not the label. The source dimmed the whole row, and doing
///   that here dragged an offline member's name below the AA contrast floor
///   (`textSecondary` is already near it); the icon and badge carry the
///   de-emphasis while the name stays readable. Not `textDisabled` either:
///   that means "not actionable", which a muted channel still is.
/// - [touch]: raises the row to [AppSizes.rowTouch]; nothing else about the
///   row changes. Left unset it follows [AppTouchTargets.of].
///
/// Keyboard focus draws a full-row outline in [AppTokens.focusRing]; selection
/// draws a left marker plus a fill in [AppTokens.accentSoft]. The two tokens
/// are byte-identical in every theme, so they are kept apart by shape rather
/// than colour: a row can be selected, unread, and focused all at once with
/// every state still legible (see the combined case in the test file).
class AppListRow extends StatefulWidget {
  const AppListRow({
    super.key,
    required this.label,
    this.leading,
    this.meta,
    this.trailing,
    this.selected = false,
    this.unread = false,
    this.muted = false,
    this.touch,
    this.height,
    this.onTap,
    this.focusNode,
    this.semanticLabel,
    this.stateDescription,
  });

  final String label;
  final Widget? leading;

  /// A short secondary caption (a timestamp, a role name), rendered in
  /// `text-secondary` regardless of the row's other states.
  final String? meta;
  final Widget? trailing;
  final bool selected;
  final bool unread;
  final bool muted;

  /// Null means "whatever this subtree is at", read from [AppTouchTargets].
  final bool? touch;

  /// Raises the row above its derived height. The member list uses this: its
  /// rows pair a larger avatar with a status dot on the corner, which crops at
  /// the channel-row default. It is a floor rather than an override, so a
  /// touch layout is never shrunk below its hit target by a caller.
  final double? height;
  final VoidCallback? onTap;

  /// Exposed for callers that need to drive focus programmatically (a
  /// command palette moving focus down a result list); the source has no
  /// equivalent since a static mockup cannot express that, but a controllable
  /// node is ordinary Flutter widget hygiene and has no visual effect on its
  /// own.
  final FocusNode? focusNode;

  /// Overrides the accessible label entirely (state suffixes below are still
  /// appended). Falls back to [label].
  final String? semanticLabel;

  /// Announced after the label, for state a sighted reader gets from the row's
  /// appearance and nobody else gets at all.
  ///
  /// [muted] deliberately announces nothing on its own: it is a wholesale
  /// visual de-emphasis with no single meaning, and its only caller uses it for
  /// an offline member, who was being announced as "muted" as a result.
  final String? stateDescription;

  /// Exposed so a test can find the left selection marker without depending
  /// on widget tree shape.
  static const Key selectionMarkerKey = Key('app_list_row_selection_marker');

  /// Exposed so a test can find the unread dot without depending on colour.
  static const Key unreadDotKey = Key('app_list_row_unread_dot');

  /// The height a row built here takes, for a sibling that must line up with
  /// one rather than centre against the taller column it sits in.
  static double heightFor(BuildContext context, {bool? touch, double? min}) {
    final density = touch ?? AppTouchTargets.of(context);
    return math.max(
      density ? AppSizes.rowTouch : AppSizes.rowPointer,
      min ?? 0,
    );
  }

  @override
  State<AppListRow> createState() => _AppListRowState();
}

class _AppListRowState extends State<AppListRow> {
  bool _hovered = false;
  bool _focused = false;

  /// A finger has no hover, so on a phone this is the only sign a tap landed
  /// before its action runs. Shown as the same raised fill hover uses, but it
  /// appears the instant the finger touches down rather than on release.
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final touch = widget.touch ?? AppTouchTargets.of(context);
    final rowHeight =
        AppListRow.heightFor(context, touch: touch, min: widget.height);

    // The source lifts colour and weight together for `selected || unread`, so
    // the dot below is what keeps unread legible when both are set at once.
    final emphasised = widget.selected || widget.unread;
    final labelStyle = AppText.ui.copyWith(
      color: emphasised ? tokens.textPrimary : tokens.textSecondary,
      fontWeight: emphasised ? AppWeights.medium : AppWeights.regular,
    );

    Widget? trailingContent = widget.trailing;
    trailingContent ??= widget.unread
        ? DecoratedBox(
            key: AppListRow.unreadDotKey,
            decoration: BoxDecoration(
              color: tokens.textPrimary,
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: const SizedBox(width: 6, height: 6),
          )
        : null;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: Row(
        spacing: AppSpacing.s8,
        children: [
          // Excluded for the same reason the label below is: an avatar names
          // itself, so a member row announced its name twice.
          if (widget.leading != null)
            ExcludeSemantics(
              child: Opacity(
                opacity: widget.muted ? 0.62 : 1,
                child: widget.leading!,
              ),
            ),
          Expanded(
            // Excluded because the Semantics wrapper below already names this
            // row; without it a screen reader announces "general, general".
            child: ExcludeSemantics(
              child: Text(widget.label,
                  overflow: TextOverflow.ellipsis, style: labelStyle),
            ),
          ),
          if (widget.meta != null)
            // Flexible, not a bare Text: ellipsis only engages under a bounded
            // width, so without this a long meta overflows instead of eliding.
            Flexible(
              child: Text(
                widget.meta!,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
          if (trailingContent != null)
            Opacity(
              opacity: widget.muted ? 0.62 : 1,
              child: trailingContent,
            ),
        ],
      ),
    );

    final visual = Container(
      height: rowHeight,
      decoration: BoxDecoration(
        color: widget.selected
            ? tokens.accentSoft
            : (_pressed || _hovered
                ? tokens.surfaceRaised
                : Colors.transparent),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              border: Border.all(color: tokens.focusRing, width: 2),
              borderRadius: BorderRadius.circular(AppRadii.control),
            )
          : null,
      child: Stack(
        // Expand, or the row's content takes its intrinsic height and a Stack
        // aligns it top-start: the icon, label and unread dot all sat above
        // the centre of a 30pt row, and higher still on a 44pt touch one.
        fit: StackFit.expand,
        children: [
          content,
          if (widget.selected)
            Positioned(
              left: 0,
              top: 5,
              bottom: 5,
              width: 2,
              child: DecoratedBox(
                key: AppListRow.selectionMarkerKey,
                decoration: BoxDecoration(
                  color: tokens.accentFill,
                  // A literal 2px in the source rather than an AppRadii
                  // step; ported as-is rather than rounded to a token.
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );

    final semanticParts = <String>[
      widget.semanticLabel ?? widget.label,
      if (widget.unread) 'unread',
      if (widget.stateDescription != null) widget.stateDescription!,
    ];

    return Semantics(
      // Its own node, not an annotation merged into whatever encloses it: the
      // rail's rows were landing in a screen-sized ancestor and vanishing,
      // which left the whole channel list unreachable to a screen reader.
      container: true,
      label: semanticParts.join(', '),
      button: widget.onTap != null,
      selected: widget.selected,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        mouseCursor:
            widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: widget.onTap == null
            ? const <Type, Action<Intent>>{}
            : <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) => widget.onTap!(),
                ),
              },
        child: GestureDetector(
          onTapDown: widget.onTap == null
              ? null
              : (_) => setState(() => _pressed = true),
          onTapUp: widget.onTap == null
              ? null
              : (_) => setState(() => _pressed = false),
          onTapCancel: widget.onTap == null
              ? null
              : () => setState(() => _pressed = false),
          onTap: widget.onTap == null
              ? null
              : () {
                  AppHaptics.selection();
                  widget.onTap!();
                },
          // Muted dims the leading and trailing content only, never the
          // label: textSecondary is already near the AA floor, and scaling
          // the whole row's opacity dragged offline member names to 3.7:1.
          child: visual,
        ),
      ),
    );
  }
}
