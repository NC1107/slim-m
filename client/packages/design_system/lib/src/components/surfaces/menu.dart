// SPDX-License-Identifier: Apache-2.0
/// A floating menu and its parts: a context menu, a dropdown, a command
/// palette result list, and the right-click/long-press sheet share this one
/// body.
///
/// [AppMenu] is one of exactly two places in this system allowed a shadow
/// ([AppShadows.menu]) rather than a hairline, because it is the one thing
/// here that is genuinely above the plane rather than part of it.
library;

import 'package:flutter/material.dart';

import '../../app_icons.dart';
import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';
import '../../touch_targets.dart';

/// A floating container for [AppMenuItem], [AppMenuLabel] and
/// [AppMenuDivider] children.
///
/// [floating] (default `true`, matching the source) toggles [AppShadows.menu];
/// a non-floating menu still gets the hairline border but sits flush rather
/// than lifted, for a menu embedded inline rather than popped over content.
class AppMenu extends StatelessWidget {
  const AppMenu(
      {super.key,
      required this.children,
      this.width = 250,
      this.floating = true});

  final List<Widget> children;
  final double width;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Semantics(
      container: true,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: floating ? AppShadows.menu : null,
        ),
        // 6 is literal in the source, not on the --space-* grid.
        padding: const EdgeInsets.all(6),
        child: Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// An uppercase micro section label inside an [AppMenu] ("Channel", "Danger
/// zone").
class AppMenuLabel extends StatelessWidget {
  const AppMenuLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Padding(
      // '8px 10px 6px' in the source: asymmetric top/bottom, literal rather
      // than on the --space-* grid.
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Text(
        text.toUpperCase(),
        style: AppText.label.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// A hairline divider between groups of [AppMenuItem]s.
class AppMenuDivider extends StatelessWidget {
  const AppMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Padding(
      // '5px 8px' in the source, literal rather than on the --space-* grid.
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: Container(height: 1, color: tokens.borderSubtle),
    );
  }
}

/// The tone an [AppMenuItem] renders in.
enum AppMenuItemTone { normal, warn, danger }

/// One row inside an [AppMenu]: an optional leading icon, a label, and
/// optional trailing content (a shortcut hint, a chevron for [submenu]).
///
/// [touch] raises the row to a literal 48px (the source's own value; no
/// [AppSizes] step matches it, the nearest being `rowTouch` at 44) and widens
/// the leading gap to `space-12`; the pointer row is 34px, which does match
/// [AppSizes.controlMd] exactly. Left unset it follows [AppTouchTargets.of].
class AppMenuItem extends StatefulWidget {
  const AppMenuItem({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.submenu = false,
    this.selected = false,
    this.tone = AppMenuItemTone.normal,
    this.touch,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final IconData? leading;
  final Widget? trailing;

  /// Adds a trailing chevron affordance for a row that opens a submenu.
  /// Combines with [trailing] rather than replacing it, matching the source's
  /// `{trailing}{submenu && <chevron>}`.
  final bool submenu;

  /// The current-value background: `accentSoft` normally, `warnSoft` when
  /// [tone] is [AppMenuItemTone.warn].
  final bool selected;
  final AppMenuItemTone tone;

  /// Null means "whatever this subtree is at", read from [AppTouchTargets].
  final bool? touch;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<AppMenuItem> createState() => _AppMenuItemState();
}

class _AppMenuItemState extends State<AppMenuItem> {
  bool _hovered = false;
  bool _focused = false;

  Color _toneColor(AppTokens tokens) => switch (widget.tone) {
        AppMenuItemTone.normal => tokens.textPrimary,
        AppMenuItemTone.warn => tokens.warnText,
        AppMenuItemTone.danger => tokens.dangerText,
      };

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final active = widget.onTap != null;
    final touch = widget.touch ?? AppTouchTargets.of(context);
    final ink = _toneColor(tokens);
    // The source dims the icon to text-secondary for the normal tone even
    // though the label itself is text-primary; warn/danger keep the icon in
    // step with the label colour.
    final iconInk =
        widget.tone == AppMenuItemTone.normal ? tokens.textSecondary : ink;

    final selectedFill = widget.tone == AppMenuItemTone.warn
        ? tokens.warnSoft
        : tokens.accentSoft;

    final content = Container(
      height: touch ? 48 : AppSizes.controlMd,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: widget.selected
            ? selectedFill
            : (_hovered ? tokens.surfaceSunken : Colors.transparent),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              border: Border.all(color: tokens.focusRing, width: 2),
              borderRadius: BorderRadius.circular(AppRadii.control),
            )
          : null,
      child: Row(
        spacing: touch ? AppSpacing.s12 : AppSpacing.s8,
        children: [
          if (widget.leading != null)
            Icon(widget.leading, size: AppSizes.icon16, color: iconInk),
          Expanded(
            // Excluded because the Semantics wrapper below already names this
            // item; merging the two doubles the announcement.
            child: ExcludeSemantics(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: (touch ? AppText.body : AppText.ui).copyWith(color: ink),
              ),
            ),
          ),
          if (widget.trailing != null || widget.submenu)
            Row(
              mainAxisSize: MainAxisSize.min,
              // 6 is literal in the source, not on the --space-* grid.
              spacing: 6,
              children: [
                if (widget.trailing != null) widget.trailing!,
                if (widget.submenu)
                  Icon(AppIcons.chevronRight,
                      size: 12, color: tokens.textSecondary),
              ],
            ),
        ],
      ),
    );

    return Semantics(
      label: widget.semanticLabel ?? widget.label,
      button: true,
      enabled: active,
      child: FocusableActionDetector(
        enabled: active,
        mouseCursor: active ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: !active
            ? const <Type, Action<Intent>>{}
            : <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) => widget.onTap!(),
                ),
              },
        child: GestureDetector(
            onTap: active ? widget.onTap : null, child: content),
      ),
    );
  }
}
