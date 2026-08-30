// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Every role, with this one member's assignments toggleable.
///
/// The inverse of `role_assign_sheet.dart`, which fixes a role and lists
/// members. Both drive the same two idempotent routes; which one you want
/// depends on whether you arrived from a role or from a person, and arriving
/// from a person is what the member profile does.
///
/// Three things here are not symmetric with that sheet and each would be a
/// real bug if copied across unchanged:
///
/// - **`@everyone` is filtered out.** The server strips it from a profile's
///   role list because every member holds it, so its toggle would render off
///   for everybody; and the assign route has no guard against it, so
///   switching it on would succeed, write a redundant row, and still read off
///   afterwards. A toggle that reports the opposite of reality and cannot be
///   switched back is the worst thing this sheet could do.
/// - **The member is re-read from the live list every build.** A profile
///   passed in by the caller is an immutable snapshot, so after the first
///   toggle every row would still be reading pre-toggle state.
/// - **A role the caller cannot grant is shown disabled, not hidden.** The
///   invite picker hides them, which is right for choosing one; here, hiding
///   a role the member actually holds would make the sheet under-report
///   somebody's privileges to the moderator reading it.
///
/// The role list grows to fit its rows, up to a ceiling, rather than always
/// claiming a fixed fraction of the window regardless of row count - the
/// same "too tall for too little content" bug
/// `overwrite_target_picker_sheets.dart` had, the inverse of avatar-crop-
/// sheet's own previously-shipped "too tall for the window" bug.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../providers/member_presence.dart' show membersProvider;
import '../providers/providers.dart';
import 'run_guarded.dart';

Future<void> showMemberRolesSheet(BuildContext context, String userId) {
  return showAppSheet<void>(
    context,
    scrolls: true,
    builder: (context) => MemberRolesSheet(userId: userId),
  );
}

class MemberRolesSheet extends ConsumerStatefulWidget {
  const MemberRolesSheet({super.key, required this.userId});

  /// The id rather than the profile, deliberately: see the library note on
  /// why a snapshot goes stale after the first toggle.
  final String userId;

  @override
  ConsumerState<MemberRolesSheet> createState() => _MemberRolesSheetState();
}

class _MemberRolesSheetState extends ConsumerState<MemberRolesSheet>
    with GuardedActionState<MemberRolesSheet> {
  Future<void> _toggle(api.Role role, bool grant) async {
    final client = ref.read(apiProvider);
    final ok = await guard(
      whatFailed: grant ? 'grant "${role.name}"' : 'take away "${role.name}"',
      action: () => grant
          ? client.assignRole(userId: widget.userId, roleId: role.id)
          : client.unassignRole(userId: widget.userId, roleId: role.id),
    );
    if (ok && mounted) ref.invalidate(membersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final roles = ref.watch(rolesProvider);
    final members = ref.watch(membersProvider);
    final mine = ref.watch(myPermissionsProvider);

    final member = members.valueOrNull
        ?.where((m) => m.id == widget.userId)
        .firstOrNull;

    // See the library doc above for why this is a ceiling, not a fixed size.
    final listCeiling = MediaQuery.sizeOf(context).height * 0.7;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s8,
            AppSpacing.s16,
            AppSpacing.s8,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              member == null ? 'Roles' : 'Roles for ${member.displayName}',
              style: AppText.heading.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
          ),
        ),
        if (actionError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            child: AppErrorState(
              message: actionError!,
              onDismiss: clearActionError,
            ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: listCeiling),
          child: AppAsyncView<List<api.Role>>(
            value: AppAsyncState(data: roles.valueOrNull, error: roles.error),
            errorMessage: 'Could not load the roles.',
            onRetry: () => ref.invalidate(rolesProvider),
            emptyMessage: 'This Space has no roles beyond @everyone.',
            isEmpty: (list) => list.every((r) => r.isEveryone),
            data: (context, list) {
              final assignable = list
                  .where((r) => !r.isEveryone)
                  .toList(growable: false);
              return ListView.builder(
                shrinkWrap: true,
                itemCount: assignable.length,
                itemBuilder: (context, i) {
                  final role = assignable[i];
                  // By id, never name: two roles can share one and both light up.
                  final held = member?.roleIds.contains(role.id) ?? false;
                  // Mirrors the server's refusal, so the toggle cannot spring back.
                  final grantable = mine.hasPermission(role.permissions);
                  return AppListRow(
                    leading: const Icon(AppIcons.shield),
                    label: role.name,
                    meta: grantable
                        ? null
                        : 'Needs permissions you do not hold',
                    trailing: AppToggle(
                      value: held,
                      onChanged: grantable && member != null
                          ? (v) => _toggle(role, v)
                          : null,
                      semanticLabel:
                          '${role.name} for '
                          '${member?.displayName ?? 'this member'}',
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
