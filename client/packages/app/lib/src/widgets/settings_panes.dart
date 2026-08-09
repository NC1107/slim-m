// SPDX-License-Identifier: Apache-2.0
/// Settings as a nav beside a pane, rather than every section stacked in one
/// scroll behind full-width hairlines.
///
/// The old shape put nine sections in a single column, each separated by a
/// divider running the whole width. That reads as one undifferentiated list:
/// nothing tells you how much there is, the dividers compete with the borders
/// of the cards inside each section, and finding "Blocked" means scrolling
/// past six things you were not looking for.
///
/// Here a pane is one idea, its own borders are the only ones in view, and the
/// nav says how many ideas there are.
///
/// **Compact drills rather than navigating.** On a phone the nav *is* the
/// screen and choosing a pane pushes it in, so there is one structure at two
/// widths instead of a separate mobile design to keep in step. The pushed pane
/// is the same widget the wide layout puts on the right.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/close_screen.dart';

/// One entry in the nav, and the pane it opens.
class SettingsPane {
  const SettingsPane({
    required this.id,
    required this.label,
    required this.builder,
    this.icon,
    this.badge,
  });

  /// Stable across rebuilds, so the selection survives a pane's own setState.
  final String id;
  final String label;

  /// Built lazily: a pane that fetches does not fetch until it is looked at,
  /// which is the other half of why this is not one long scroll.
  final WidgetBuilder builder;

  /// Drawn plain, matching every other settings row in this app
  /// ([SpaceSettingsSection], `DevicesSection`, `BlockedSection`): the nav
  /// list is what read as text-and-a-chevron with nothing else beside it.
  final IconData? icon;

  /// A count shown at the trailing edge, for a pane whose interest is how
  /// many things are in it.
  final String? badge;
}

/// A labelled run of panes: `YOU`, `CALLS`, `SAFETY`.
class SettingsPaneGroup {
  const SettingsPaneGroup({required this.label, required this.panes});

  final String label;
  final List<SettingsPane> panes;
}

/// Widest a nav column gets. Below this the nav is the whole screen.
const double _twoPaneFloor = 800;

class SettingsPanesScaffold extends StatefulWidget {
  const SettingsPanesScaffold({
    super.key,
    required this.title,
    required this.groups,
    required this.backTooltip,
    required this.backFallback,
    this.footer,
  });

  final String title;
  final List<SettingsPaneGroup> groups;

  /// Names the destination, not just "Back"; see [BackToButton].
  final String backTooltip;
  final String backFallback;

  /// Below the nav, pinned: sign out. Who-you-are lives inside the "Account &
  /// presence" pane itself now, not above the nav as a second, editable copy
  /// of the same identity - see that pane's own doc comment.
  final Widget? footer;

  @override
  State<SettingsPanesScaffold> createState() => _SettingsPanesScaffoldState();
}

class _SettingsPanesScaffoldState extends State<SettingsPanesScaffold> {
  String? _selectedId;

  List<SettingsPane> get _allPanes => [
    for (final group in widget.groups) ...group.panes,
  ];

  SettingsPane? get _selected {
    final panes = _allPanes;
    if (panes.isEmpty) return null;
    return panes.where((p) => p.id == _selectedId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final wide = MediaQuery.sizeOf(context).width >= _twoPaneFloor;
    final panes = _allPanes;

    // Wide always shows something: an empty pane beside a nav is a hole.
    final selected = wide ? (_selected ?? panes.firstOrNull) : _selected;

    if (!wide && selected != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(selected.label),
          leading: IconButton(
            icon: const Icon(AppIcons.back),
            tooltip: 'Back to ${widget.title.toLowerCase()}',
            onPressed: () => setState(() => _selectedId = null),
          ),
        ),
        body: SafeArea(top: false, child: _PaneBody(pane: selected)),
      );
    }

    final nav = _Nav(
      groups: widget.groups,
      selectedId: selected?.id,
      // Wide only: on compact no lit row is ever visible beside its pane.
      showSelection: wide,
      footer: widget.footer,
      onSelect: (id) => setState(() => _selectedId = id),
    );

    if (!wide) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: BackToButton(
            tooltip: widget.backTooltip,
            fallback: widget.backFallback,
          ),
        ),
        body: SafeArea(top: false, child: nav),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: BackToButton(
          tooltip: widget.backTooltip,
          fallback: widget.backFallback,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 240,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: tokens.borderSubtle)),
                ),
                child: nav,
              ),
            ),
            Expanded(
              child: selected == null
                  ? const SizedBox.shrink()
                  : _PaneBody(pane: selected),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pane's own content, keyed by its id so switching panes does not carry the
/// previous one's scroll offset or form state across.
///
/// Capped at [AppContentColumn]'s own width and centred, or a pane's rows
/// stretch across whatever the window happens to be - the owner's own "very
/// flat" report on a wide desktop window, where the nav's 240px left nothing
/// else bounding it.
class _PaneBody extends StatelessWidget {
  const _PaneBody({required this.pane});

  final SettingsPane pane;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey(pane.id),
    child: AppContentColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [Builder(builder: pane.builder)],
      ),
    ),
  );
}

class _Nav extends StatelessWidget {
  const _Nav({
    required this.groups,
    required this.selectedId,
    required this.showSelection,
    required this.onSelect,
    this.footer,
  });

  final List<SettingsPaneGroup> groups;
  final String? selectedId;
  final bool showSelection;
  final void Function(String) onSelect;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s12,
            ),
            children: [
              for (final group in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, AppSpacing.s12, 10, 6),
                  child: Semantics(
                    header: true,
                    child: Text(
                      group.label.toUpperCase(),
                      style: AppText.label.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
                for (final pane in group.panes)
                  AppListRow(
                    label: pane.label,
                    leading: pane.icon == null ? null : Icon(pane.icon),
                    meta: pane.badge,
                    selected: showSelection && pane.id == selectedId,
                    // A chevron only where the row actually goes somewhere.
                    trailing: showSelection
                        ? null
                        : Icon(
                            AppIcons.chevronRight,
                            size: AppSizes.icon16,
                            color: tokens.textSecondary,
                          ),
                    onTap: () => onSelect(pane.id),
                  ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(padding: const EdgeInsets.all(AppSpacing.s8), child: footer!),
      ],
    );
  }
}
