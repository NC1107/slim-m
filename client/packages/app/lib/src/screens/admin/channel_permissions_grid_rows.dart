// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The permissions grid's presentational rows: the legend, the header row of
/// principal columns, a group header, one permission row, and one tri-state
/// cell. Split out of `channel_permissions_grid.dart`, which owns the state
/// and pending-changes logic these render.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

/// One grid column: the role or member it targets, resolved for display.
class GridColumn {
  const GridColumn({
    required this.kind,
    required this.id,
    required this.label,
    required this.isBot,
  });

  final api.OverwriteTarget kind;
  final String id;
  final String label;
  final bool isBot;

  String get key => '${kind.wire}:$id';
}

enum CellState { allow, inherit, deny }

/// The column width every header, group header and row aligns its label
/// column and cell columns to.
const double gridLabelWidth = 220;
const double gridCellWidth = 72;

class Legend extends StatelessWidget {
  const Legend({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    Widget item(IconData icon, Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
    return Wrap(
      spacing: AppSpacing.s16,
      runSpacing: AppSpacing.s4,
      children: [
        item(AppIcons.check, tokens.status.online, 'Allow'),
        item(AppIcons.shapeArrow, tokens.textSecondary, 'Inherit from role'),
        item(AppIcons.dismiss, tokens.dangerText, 'Deny'),
        item(
          AppIcons.restrictedChannel,
          tokens.textSecondary,
          "you can't grant this",
        ),
      ],
    );
  }
}

class HeaderRow extends StatelessWidget {
  const HeaderRow({
    super.key,
    required this.columns,
    required this.onAdd,
    required this.onRemove,
  });

  final List<GridColumn> columns;
  final VoidCallback onAdd;

  /// Removing a column clears its pending state - a full inherit, applied on
  /// save the same way any other pending edit is.
  final ValueChanged<GridColumn> onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(width: gridLabelWidth),
            for (final column in columns)
              _HeaderCell(column: column, onRemove: () => onRemove(column)),
            SizedBox(
              width: gridCellWidth,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                child: Center(
                  child: AppIconButton(
                    icon: AppIcons.add,
                    semanticLabel: 'Add a role or member to this grid',
                    onPressed: onAdd,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.column, required this.onRemove});

  final GridColumn column;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SizedBox(
      width: gridCellWidth,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            column.kind == api.OverwriteTarget.role
                ? Icon(
                    AppIcons.shield,
                    size: AppSizes.icon16,
                    color: tokens.textSecondary,
                  )
                : AppAvatar(
                    name: column.label,
                    tintKey: column.id,
                    size: 20,
                    shape: column.isBot
                        ? AppAvatarShape.square
                        : AppAvatarShape.circle,
                  ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              column.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: tokens.textPrimary),
            ),
            GestureDetector(
              onTap: onRemove,
              child: Semantics(
                button: true,
                label: 'Remove ${column.label} from this grid',
                child: Icon(
                  AppIcons.dismiss,
                  size: 11,
                  color: tokens.textDisabled,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GroupHeaderRow extends StatelessWidget {
  const GroupHeaderRow({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        gridLabelWidth,
        AppSpacing.s12,
        0,
        AppSpacing.s4,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: AppText.micro.copyWith(
            color: tokens.textDisabled,
            fontWeight: AppWeights.medium,
          ),
        ),
      ),
    );
  }
}

class GridRow extends StatelessWidget {
  const GridRow({
    super.key,
    required this.label,
    required this.columns,
    required this.cellBuilder,
  });

  final String label;
  final List<GridColumn> columns;
  final Widget Function(GridColumn column) cellBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          SizedBox(
            width: gridLabelWidth,
            child: Text(
              label,
              style: AppText.ui.copyWith(
                color: tokens.textPrimary,
                fontSize: 13.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final column in columns)
            SizedBox(
              width: gridCellWidth,
              child: Center(child: cellBuilder(column)),
            ),
          const SizedBox(width: gridCellWidth),
        ],
      ),
    );
  }
}

class Cell extends StatelessWidget {
  const Cell({
    super.key,
    required this.state,
    required this.disabled,
    required this.onTap,
  });

  final CellState state;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Only Allow is ever blocked; Deny needs no permission, so the cell always stays tappable.
    final (color, icon) = switch (state) {
      CellState.allow => (tokens.status.online, AppIcons.check),
      CellState.deny => (tokens.dangerText, AppIcons.dismiss),
      CellState.inherit when disabled => (
        tokens.textDisabled,
        AppIcons.restrictedChannel,
      ),
      CellState.inherit => (tokens.textSecondary, null),
    };
    final boxed = state != CellState.inherit;
    return Semantics(
      button: true,
      label: switch (state) {
        CellState.allow => 'Allow',
        CellState.deny => 'Deny',
        CellState.inherit =>
          disabled ? "Inherit; you can't grant this" : 'Inherit from role',
      },
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: boxed ? color.withValues(alpha: 0.12) : null,
            border: boxed ? Border.all(color: color) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(
            width: 30,
            height: 26,
            child: Icon(icon ?? AppIcons.shapeArrow, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}

class AddColumnKindSheet extends StatelessWidget {
  const AddColumnKindSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppListRow(
          leading: const Icon(AppIcons.shield),
          label: 'Add a role',
          onTap: () => Navigator.of(context).pop(api.OverwriteTarget.role),
        ),
        AppListRow(
          leading: const Icon(AppIcons.account),
          label: 'Add a member',
          onTap: () => Navigator.of(context).pop(api.OverwriteTarget.member),
        ),
      ],
    ),
  );
}
