// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Presents the options of an [AppControlWithOptions]: the anchored menu on a
/// wide layout and the bottom sheet on a compact one, through the same
/// [ContextMenuRegion] every other menu here uses.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'context_menu_region.dart';

/// One row of a control's options menu.
class ControlOption {
  const ControlOption({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.tone = AppMenuItemTone.normal,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final AppMenuItemTone tone;
}

/// [child] with a caret and long-press that open [options].
///
/// An empty [options] draws [child] alone, so a caller can pass whatever is
/// currently possible without its own branch.
class ControlOptionsMenu extends StatefulWidget {
  const ControlOptionsMenu({
    super.key,
    required this.child,
    required this.options,
    required this.optionsLabel,
    this.active = false,
  });

  final Widget child;
  final List<ControlOption> options;
  final String optionsLabel;
  final bool active;

  @override
  State<ControlOptionsMenu> createState() => _ControlOptionsMenuState();
}

class _ControlOptionsMenuState extends State<ControlOptionsMenu> {
  final _region = GlobalKey<ContextMenuRegionState>();

  /// Keeps the control's focus and press state when options appear or go, as
  /// the share button does on starting a share with the keyboard.
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (widget.options.isEmpty) return child;
    return ContextMenuRegion(
      key: _region,
      // The wrapped control is already a tab stop, and owns the long-press.
      ownsFocusNode: false,
      enableLongPress: false,
      itemsBuilder: (context, close) => [
        for (final option in widget.options)
          AppMenuItem(
            label: option.label,
            leading: option.icon,
            tone: option.tone,
            onTap: () {
              close();
              option.onSelected();
            },
          ),
      ],
      child: AppControlWithOptions(
        active: widget.active,
        optionsLabel: widget.optionsLabel,
        onOpenOptions: () => _region.currentState?.open(),
        child: child,
      ),
    );
  }
}
