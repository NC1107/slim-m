// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// One channel's permission overwrites as a grid: a column per principal
/// with (or being given) an overwrite, a row per permission, grouped. Each
/// cell is tri-state (allow/inherit/deny). Replaces the old "pick a target,
/// set every permission at once" flow (`current_overwrites_section.dart`,
/// `overwrite_target_picker_sheets.dart`'s role/member pickers, and
/// `permission_overwrite_row.dart`), which made a routine one-cell change a
/// full-overwrite resubmission.
///
/// Edits batch the same way the roles pane's Permissions tab does: every
/// cell tap only touches local state until Save, which applies the whole
/// pending set in one `batchSetChannelOverwrites` call. This file owns that
/// state; `channel_permissions_grid_rows.dart` is the presentational half.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart' show Channel;
import 'package:slimm_design_system/design_system.dart';

import '../../permissions.dart';
import '../../providers/admin_providers.dart';
import '../../providers/channel_permissions.dart';
import '../../providers/member_presence.dart' show membersProvider;
import '../../providers/providers.dart';
import '../../widgets/run_guarded.dart';
import 'channel_permissions_grid_rows.dart';
import 'overwrite_target_picker_sheets.dart';

class ChannelPermissionsGrid extends ConsumerStatefulWidget {
  const ChannelPermissionsGrid({super.key, required this.channel});

  final Channel channel;

  @override
  ConsumerState<ChannelPermissionsGrid> createState() =>
      _ChannelPermissionsGridState();
}

class _ChannelPermissionsGridState extends ConsumerState<ChannelPermissionsGrid>
    with GuardedActionState<ChannelPermissionsGrid> {
  /// `column.key` -> (allow, deny), for every column currently shown -
  /// loaded overwrites plus anything a pending edit or a freshly added
  /// column has touched.
  Map<String, (int, int)> _pending = {};
  Map<String, (int, int)> _original = {};

  /// Columns added locally that never had a saved overwrite yet, so a
  /// pending removal of one is a local drop rather than a `DELETE` call.
  final Set<String> _addedLocally = {};

  /// Columns that existed in [_original] but the caller removed; cleared via
  /// `deleteChannelOverwrite` on save.
  final Set<String> _removed = {};

  bool _saving = false;
  bool _loaded = false;

  void _seedFrom(List<api.ChannelOverwrite> overwrites) {
    if (_loaded) return;
    _loaded = true;
    _original = {
      for (final o in overwrites) '${o.kind.wire}:${o.id}': (o.allow, o.deny),
    };
    _pending = {..._original};
  }

  bool get _isDirty {
    if (_removed.isNotEmpty) return true;
    for (final entry in _pending.entries) {
      if (_original[entry.key] != entry.value) return true;
    }
    return false;
  }

  int get _changeCount {
    var count = _removed.length;
    for (final entry in _pending.entries) {
      if (_original[entry.key] != entry.value) count++;
    }
    return count;
  }

  void _cycle(GridColumn column, int bit, bool grantable) {
    final (allow, deny) = _pending[column.key] ?? (0, 0);
    final state = allow & bit != 0
        ? CellState.allow
        : deny & bit != 0
        ? CellState.deny
        : CellState.inherit;
    final next = switch (state) {
      CellState.inherit => grantable ? CellState.allow : CellState.deny,
      CellState.allow => CellState.deny,
      CellState.deny => CellState.inherit,
    };
    setState(() {
      var newAllow = allow & ~bit;
      var newDeny = deny & ~bit;
      switch (next) {
        case CellState.allow:
          newAllow |= bit;
        case CellState.deny:
          newDeny |= bit;
        case CellState.inherit:
          break;
      }
      _pending[column.key] = (newAllow, newDeny);
    });
  }

  void _addColumn(GridColumn column) {
    setState(() {
      _pending.putIfAbsent(column.key, () => (0, 0));
      if (!_original.containsKey(column.key)) _addedLocally.add(column.key);
      _removed.remove(column.key);
    });
  }

  void _removeColumn(GridColumn column) {
    setState(() {
      _pending.remove(column.key);
      if (_original.containsKey(column.key)) {
        _removed.add(column.key);
      }
      _addedLocally.remove(column.key);
    });
  }

  void _discard() {
    setState(() {
      _pending = {..._original};
      _addedLocally.clear();
      _removed.clear();
    });
  }

  Future<void> _pickTarget() async {
    final kind = await showAppSheet<api.OverwriteTarget>(
      context,
      builder: (context) => const AddColumnKindSheet(),
    );
    if (kind == null || !mounted) return;
    if (kind == api.OverwriteTarget.role) {
      final role = await showAppSheet<api.Role>(
        context,
        builder: (context) => const RolePickerSheet(),
      );
      if (role != null) {
        _addColumn(
          GridColumn(
            kind: api.OverwriteTarget.role,
            id: role.id,
            label: role.name,
            isBot: false,
          ),
        );
      }
    } else {
      final member = await showAppSheet<api.UserProfile>(
        context,
        builder: (context) => const MemberPickerSheet(),
      );
      if (member != null) {
        _addColumn(
          GridColumn(
            kind: api.OverwriteTarget.member,
            id: member.id,
            label: member.displayName,
            isBot: member.isBot,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await guard(
      whatFailed: 'save the permissions grid',
      action: () async {
        for (final key in _removed) {
          final (kind, id) = _parseKey(key);
          await ref
              .read(apiProvider)
              .deleteChannelOverwrite(
                channelId: widget.channel.id,
                kind: kind,
                id: id,
              );
        }
        final edits = <api.ChannelOverwriteEdit>[
          for (final entry in _pending.entries)
            if (_original[entry.key] != entry.value)
              api.ChannelOverwriteEdit(
                kind: _parseKey(entry.key).$1,
                id: _parseKey(entry.key).$2,
                allow: entry.value.$1,
                deny: entry.value.$2,
              ),
        ];
        if (edits.isNotEmpty) {
          await ref
              .read(apiProvider)
              .batchSetChannelOverwrites(
                channelId: widget.channel.id,
                overwrites: edits,
              );
        }
      },
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _loaded = false;
      _addedLocally.clear();
      _removed.clear();
      ref.invalidate(channelOverwritesProvider(widget.channel.id));
    }
  }

  static (api.OverwriteTarget, String) _parseKey(String key) {
    final i = key.indexOf(':');
    final kind = key.substring(0, i) == 'role'
        ? api.OverwriteTarget.role
        : api.OverwriteTarget.member;
    return (kind, key.substring(i + 1));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final overwritesAsync = ref.watch(
      channelOverwritesProvider(widget.channel.id),
    );
    final rolesAsync = ref.watch(rolesProvider);
    final membersAsync = ref.watch(membersProvider);
    final myPermissions = ref.watch(
      myChannelPermissionsProvider(widget.channel.id),
    );

    if (!overwritesAsync.hasValue ||
        !rolesAsync.hasValue ||
        !membersAsync.hasValue) {
      if (overwritesAsync.hasError) {
        return AppErrorState(
          message: "Could not load this channel's overwrites.",
          onRetry: () =>
              ref.invalidate(channelOverwritesProvider(widget.channel.id)),
        );
      }
      if (rolesAsync.hasError) {
        return AppErrorState(
          message: 'Could not load roles.',
          onRetry: () => ref.invalidate(rolesProvider),
        );
      }
      if (membersAsync.hasError) {
        return AppErrorState(
          message: 'Could not load members.',
          onRetry: () => ref.invalidate(membersProvider),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    _seedFrom(overwritesAsync.requireValue);
    final roles = rolesAsync.requireValue;
    final members = membersAsync.requireValue;
    final everyone = roles.where((r) => r.isEveryone).firstOrNull;

    final columns = <GridColumn>[
      if (everyone != null)
        GridColumn(
          kind: api.OverwriteTarget.role,
          id: everyone.id,
          label: everyone.name,
          isBot: false,
        ),
      for (final key in _pending.keys)
        if (everyone == null || key != 'role:${everyone.id}')
          if (_resolve(key, roles, members) case final column?) column,
    ];

    // Embedded inline (unbounded height) or given the whole body (bounded); Expanded below needs a ceiling either way.
    return LayoutBuilder(
      builder: (context, outer) {
        final maxHeight = outer.hasBoundedHeight
            ? outer.maxHeight
            : MediaQuery.sizeOf(context).height * 0.6;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: _buildGrid(context, tokens, columns, myPermissions),
        );
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    AppTokens tokens,
    List<GridColumn> columns,
    int myPermissions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s20,
            AppSpacing.s12,
            AppSpacing.s20,
            AppSpacing.s8,
          ),
          child: const Legend(),
        ),
        if (actionError case final error?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
            child: AppErrorState(message: error, onDismiss: clearActionError),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, viewport) {
              // Content width or viewport, whichever is wider; a bare minWidth constraint here leaves maxWidth infinite and crashes the stretching column below.
              final contentWidth =
                  gridLabelWidth + (columns.length + 1) * gridCellWidth;
              final totalWidth = contentWidth < viewport.maxWidth
                  ? viewport.maxWidth
                  : contentWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HeaderRow(
                        columns: columns,
                        onAdd: _pickTarget,
                        onRemove: _removeColumn,
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.s16,
                          ),
                          children: [
                            for (final group in Perm.groups) ...[
                              GroupHeaderRow(title: group.title),
                              for (final spec in group.permissions)
                                GridRow(
                                  label: spec.label,
                                  columns: columns,
                                  cellBuilder: (column) {
                                    final grantable = myPermissions
                                        .hasPermission(spec.bit);
                                    final (allow, deny) =
                                        _pending[column.key] ?? (0, 0);
                                    final state = allow & spec.bit != 0
                                        ? CellState.allow
                                        : deny & spec.bit != 0
                                        ? CellState.deny
                                        : CellState.inherit;
                                    return Cell(
                                      state: state,
                                      disabled: !grantable,
                                      onTap: () =>
                                          _cycle(column, spec.bit, grantable),
                                    );
                                  },
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_isDirty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              0,
              AppSpacing.s16,
              AppSpacing.s16,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surfaceBase,
                border: Border.all(color: tokens.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: AppShadows.float,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  AppSpacing.s8,
                  AppSpacing.s8,
                  AppSpacing.s8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$_changeCount unsaved ${_changeCount == 1 ? 'change' : 'changes'}',
                        style: AppText.ui.copyWith(color: tokens.textPrimary),
                      ),
                    ),
                    AppButton(
                      label: 'Discard',
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.sm,
                      disabled: _saving,
                      onPressed: _discard,
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    AppButton(
                      label: _saving ? 'Saving...' : 'Save changes',
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.sm,
                      disabled: _saving,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  GridColumn? _resolve(
    String key,
    List<api.Role> roles,
    List<api.UserProfile> members,
  ) {
    final (kind, id) = _parseKey(key);
    if (kind == api.OverwriteTarget.role) {
      final role = roles.where((r) => r.id == id).firstOrNull;
      if (role == null) return null;
      return GridColumn(kind: kind, id: id, label: role.name, isBot: false);
    }
    final member = members.where((m) => m.id == id).firstOrNull;
    if (member == null) return null;
    return GridColumn(
      kind: kind,
      id: id,
      label: member.displayName,
      isBot: member.isBot,
    );
  }
}
