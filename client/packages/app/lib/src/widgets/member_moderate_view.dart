// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The card's "Moderate..." sub-view: everything that used to be seven
/// top-level rows lives here instead, one step in from the profile.
///
/// Members without any of these rights never see the row that opens this at
/// all - see `member_profile.dart`'s own `showModeration` - so this view
/// itself never has to re-check "does the caller have any rights here".
///
/// Roles are a checkbox list rather than `member_roles_sheet.dart`'s own
/// sheet: the design folds role editing into Moderate rather than a second
/// surface. `@everyone` is shown, not filtered out as that sheet did, always
/// checked and always locked - every member holds it, and nothing here can
/// change that. A role the caller cannot grant is shown disabled, not
/// hidden, so this never under-reports somebody's privileges; see that
/// file's own library doc for the same reasoning this reuses.
///
/// This calls the same `assignRole`/`unassignRole` routes the Space Settings
/// roles screen uses, not a new one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../providers/member_presence.dart' show membersProvider;
import '../providers/providers.dart';
import 'member_profile_sections.dart';
import 'reset_code_sheet.dart';
import 'run_guarded.dart';

class MemberModerateView extends ConsumerStatefulWidget {
  const MemberModerateView({
    super.key,
    required this.profile,
    required this.host,
    required this.canManageRoles,
    required this.canOfferTimeoutChips,
    required this.canIssueReset,
    required this.canRemove,
    required this.canEject,
    required this.onBack,
    required this.onTimeOut,
    required this.onRemove,
    required this.onEject,
    required this.onDone,
  });

  final api.UserProfile profile;

  /// A context that outlives the popover; see `member_profile.dart`'s `host`.
  final BuildContext host;

  final bool canManageRoles;
  final bool canOfferTimeoutChips;
  final bool canIssueReset;
  final bool canRemove;
  final bool canEject;

  final VoidCallback onBack;
  final void Function(Duration) onTimeOut;
  final VoidCallback onRemove;
  final VoidCallback onEject;
  final VoidCallback onDone;

  @override
  ConsumerState<MemberModerateView> createState() => _MemberModerateViewState();
}

class _MemberModerateViewState extends ConsumerState<MemberModerateView>
    with GuardedActionState<MemberModerateView> {
  Future<void> _toggleRole(api.Role role, bool grant) async {
    final client = ref.read(apiProvider);
    final ok = await guard(
      whatFailed: grant ? 'grant "${role.name}"' : 'take away "${role.name}"',
      action: () => grant
          ? client.assignRole(userId: widget.profile.id, roleId: role.id)
          : client.unassignRole(userId: widget.profile.id, roleId: role.id),
    );
    if (ok && mounted) ref.invalidate(membersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final roles = ref.watch(rolesProvider).valueOrNull ?? const <api.Role>[];
    final mine = ref.watch(myPermissionsProvider);
    // Re-read live, or a toggle just above keeps reading a stale snapshot.
    final live = ref
        .watch(membersProvider)
        .valueOrNull
        ?.where((m) => m.id == widget.profile.id)
        .firstOrNull;
    final heldIds = live?.roleIds ?? widget.profile.roleIds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s8,
            AppSpacing.s8,
            AppSpacing.s12,
            AppSpacing.s8,
          ),
          child: Row(
            children: [
              AppIconButton(
                icon: AppIcons.back,
                semanticLabel: 'Back to profile',
                tooltip: 'Back',
                size: AppIconButtonSize.sm,
                onPressed: widget.onBack,
              ),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Text(
                  'Moderate ${widget.profile.displayName}',
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: AppWeights.semi,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.canManageRoles) ...[
          const AppMenuLabel('ROLES'),
          for (final role in roles)
            _RoleRow(
              role: role,
              held: role.isEveryone || heldIds.contains(role.id),
              grantable:
                  !role.isEveryone && mine.hasPermission(role.permissions),
              memberName: widget.profile.displayName,
              onChanged: (v) => _toggleRole(role, v),
            ),
          const AppMenuDivider(),
        ],
        if (widget.canOfferTimeoutChips) ...[
          const AppMenuLabel('TIME OUT'),
          TimeoutDurationChips(onChosen: widget.onTimeOut),
          const AppMenuDivider(),
        ],
        if (widget.canEject) ...[
          AppMenuItem(
            label: 'Eject from call...',
            leading: AppIcons.leaveCall,
            tone: AppMenuItemTone.danger,
            onTap: widget.onEject,
          ),
          const AppMenuDivider(),
        ],
        if (widget.canIssueReset) ...[
          const AppMenuLabel('ACCOUNT'),
          ResetCodeMenuItem(
            host: widget.host,
            subjectId: widget.profile.id,
            subjectName: widget.profile.displayName,
            onDone: widget.onDone,
          ),
        ],
        if (actionError != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s8),
            child: AppErrorState(
              message: actionError!,
              onDismiss: clearActionError,
            ),
          ),
        if (widget.canRemove)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s8,
              AppSpacing.s12,
              AppSpacing.s12,
            ),
            child: AppButton(
              label: 'Remove from Space...',
              variant: AppButtonVariant.danger,
              full: true,
              onPressed: widget.onRemove,
            ),
          ),
      ],
    );
  }
}

/// One role's checkbox row. `@everyone` arrives already locked (`grantable`
/// false and `held` true), so it renders the same as any role the caller
/// cannot toggle - the design's own "shown but locked".
class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.role,
    required this.held,
    required this.grantable,
    required this.memberName,
    required this.onChanged,
  });

  final api.Role role;
  final bool held;
  final bool grantable;
  final String memberName;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AppListRow(
      leading: Icon(AppIcons.shield, color: tokens.textSecondary),
      label: role.name,
      meta: role.isEveryone
          ? 'Always granted'
          : (grantable ? null : 'Needs permissions you do not hold'),
      trailing: AppToggle(
        value: held,
        onChanged: (!role.isEveryone && grantable) ? (v) => onChanged(v) : null,
        semanticLabel: '${role.name} for $memberName',
      ),
    );
  }
}
