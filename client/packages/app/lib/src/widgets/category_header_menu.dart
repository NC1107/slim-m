// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A category header's own context menu (rename, move, collapse, delete)
/// plus its drag grip and drop target - split out of
/// `channel_rail_sections.dart` for the review budget. The null,
/// id-less implicit "Channels" section never reaches this: it has nothing
/// here to manage.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/collapsed_categories_preference.dart';
import 'channel_category_drag.dart';
import 'context_menu_region.dart';
import 'manage_category_sheet.dart';

class CategoryHeaderMenu extends ConsumerWidget {
  const CategoryHeaderMenu({
    super.key,
    required this.category,
    required this.categories,
    required this.collapsed,
    required this.label,
  });

  final ChannelCategoryRow category;

  /// Every real category, in the order the rail currently shows them - the
  /// full list [moveCategoryAndReport] and the drag target both need to
  /// compute a new arrangement, not just this one row.
  final List<ChannelCategoryRow> categories;
  final Set<String> collapsed;
  final Widget label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryIndex = categories.indexWhere((c) => c.id == category.id);
    final isCollapsed = collapsed.contains(category.id);
    // Both verbs directly: deleting used to be a menu, a sheet, a danger zone and a confirmation.
    final menu = ContextMenuRegion(
      itemsBuilder: (context, close) => [
        AppMenuItem(
          label: 'Rename category...',
          leading: AppIcons.edit,
          onTap: () {
            close();
            showManageCategorySheet(context, category);
          },
        ),
        if (categoryIndex > 0)
          AppMenuItem(
            label: 'Move category up',
            leading: AppIcons.moveUp,
            onTap: () {
              close();
              unawaited(
                moveCategoryAndReport(context, ref, categories, category, -1),
              );
            },
          ),
        if (categoryIndex >= 0 && categoryIndex < categories.length - 1)
          AppMenuItem(
            label: 'Move category down',
            leading: AppIcons.moveDown,
            onTap: () {
              close();
              unawaited(
                moveCategoryAndReport(context, ref, categories, category, 1),
              );
            },
          ),
        AppMenuItem(
          label: isCollapsed ? 'Expand category' : 'Collapse category',
          leading: isCollapsed ? AppIcons.unfold : AppIcons.fold,
          onTap: () {
            close();
            unawaited(
              ref
                  .read(collapsedCategoriesProvider.notifier)
                  .toggle(category.id),
            );
          },
        ),
        AppMenuItem(
          label: 'Delete category...',
          leading: AppIcons.delete,
          tone: AppMenuItemTone.danger,
          onTap: () {
            close();
            unawaited(confirmAndDeleteCategory(context, ref, category));
          },
        ),
      ],
      child: label,
    );
    // The grip is the drag source; the whole row is the drop target, so a drag can land anywhere over a header.
    return CategoryDragTarget(
      category: category,
      ordered: categories,
      child: Row(
        children: [
          CategoryDragGrip(category: category),
          Expanded(child: menu),
        ],
      ),
    );
  }
}
