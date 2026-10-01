// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A menu that keeps its first step short and puts the rest behind "More".
///
/// `docs/design/desktop-vs-mobile.md` caps a menu at about 8 rows; the rest
/// moves one step in rather than growing the menu past half the window.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class MenuWithMore extends StatefulWidget {
  const MenuWithMore({super.key, required this.primary, required this.more});

  final List<Widget> primary;
  final List<Widget> more;

  @override
  State<MenuWithMore> createState() => _MenuWithMoreState();
}

class _MenuWithMoreState extends State<MenuWithMore> {
  bool _showingMore = false;

  @override
  Widget build(BuildContext context) {
    final rows = _showingMore
        ? [
            AppMenuItem(
              label: 'Back',
              leading: AppIcons.back,
              onTap: () => setState(() => _showingMore = false),
            ),
            const AppMenuDivider(),
            ...widget.more,
          ]
        : [
            ...widget.primary,
            if (widget.more.isNotEmpty)
              AppMenuItem(
                label: 'More',
                leading: AppIcons.moreHorizontal,
                submenu: true,
                onTap: () => setState(() => _showingMore = true),
              ),
          ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
