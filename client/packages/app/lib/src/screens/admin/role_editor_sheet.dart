// SPDX-License-Identifier: Apache-2.0
/// The create/edit form for a role: `POST /roles` and `PATCH /roles/{id}`.
///
/// A permission toggle is only interactive when the signed-in caller holds
/// that bit themselves. The server refuses a create or update that would
/// hand out (or leave assigned) a bit the caller does not hold, so a
/// disabled toggle here is not a UI nicety layered over a request that
/// would work anyway; it is the same rule, shown before the round trip
/// rather than after a 403.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../api_failure.dart';
import '../../permissions.dart';
import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';

Future<void> showRoleEditorSheet(BuildContext context, {api.Role? role}) {
  return showAppSheet<void>(
    context,
    scrolls: true,
    builder: (context) => _RoleEditorSheet(role: role),
  );
}

class _RoleEditorSheet extends ConsumerStatefulWidget {
  const _RoleEditorSheet({this.role});

  final api.Role? role;

  @override
  ConsumerState<_RoleEditorSheet> createState() => _RoleEditorSheetState();
}

class _RoleEditorSheetState extends ConsumerState<_RoleEditorSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.role?.name ?? '',
  );
  late int _permissions = widget.role?.permissions ?? 0;
  bool _submitting = false;
  String? _error;

  bool get _isCreate => widget.role == null;
  bool get _canSubmit => !_submitting && _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// On edit, the permission bitmask is omitted rather than resent when nothing
  /// changed: a role can carry a bit this caller does not hold (granted by
  /// someone with a wider set), and resending it verbatim would still be
  /// refused as "not a subset of the caller's own permissions" even though
  /// nothing moved.
  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_isCreate) {
        await ref
            .read(apiProvider)
            .createRole(name: _name.text.trim(), permissions: _permissions);
      } else {
        final changed = _permissions != widget.role!.permissions;
        await ref
            .read(apiProvider)
            .updateRole(
              roleId: widget.role!.id,
              name: _name.text.trim(),
              permissions: changed ? _permissions : null,
            );
      }
      if (context.mounted) ref.invalidate(rolesProvider);
      if (mounted) Navigator.of(context).pop();
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure(
          _isCreate ? 'create the role' : 'save the role',
          e,
        );
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final myPermissions = ref.watch(myPermissionsProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.s16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isCreate ? 'New role' : 'Edit role',
              style: AppText.heading.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            AppInput(
              controller: _name,
              placeholder: 'Role name',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Permissions',
              style: AppText.label.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s4),
            for (final (bit, label) in Perm.editable)
              _PermissionRow(
                label: label,
                value: _permissions.hasPermission(bit),
                enabled: myPermissions.hasPermission(bit),
                onChanged: (v) => setState(() {
                  _permissions = v
                      ? (_permissions | bit)
                      : (_permissions & ~bit);
                }),
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s8),
              AppErrorState(message: _error!),
            ],
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: _submitting
                  ? 'Saving...'
                  : (_isCreate ? 'Create role' : 'Save changes'),
              variant: AppButtonVariant.primary,
              full: true,
              disabled: !_canSubmit,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.ui.copyWith(
                color: enabled ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ),
          AppToggle(
            value: value,
            onChanged: enabled ? onChanged : null,
            semanticLabel: label,
          ),
        ],
      ),
    );
  }
}
