// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Account recovery: issuing a member a one-time password reset code.
///
/// The action itself already shipped, on a member's profile popover. Nothing
/// in Space settings mentioned recovery at all, so an administrator looking
/// for it there - which is where an admin action is expected to live - found
/// nothing and concluded the feature was missing. This is a second way in, not
/// a move: [ResetCodeMenuItem] on the popover still works and is still the
/// fastest route when you already have the person in front of you.
///
/// ADMINISTRATOR, matching `POST /admin/users/{id}/reset-code`, which refuses
/// anything less. Issuing a code is a way into somebody else's account, so it
/// asks for more than the MANAGE_SERVER that gates most of Space settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'package:slimm_api/api.dart' as api;

import '../../permissions.dart';
import '../../providers/admin_providers.dart';
import '../../routing/routes.dart';
import '../../widgets/reset_code_sheet.dart';
import '../../widgets/settings_section_header.dart';
import '../settings_screen_scaffold.dart';
import 'overwrite_target_picker_sheets.dart';

class AccountRecoveryScreen extends StatelessWidget {
  const AccountRecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsScreenScaffold(
    title: 'Account recovery',
    backTooltip: 'Back to Space settings',
    backFallback: Routes.spaceSettings,
    child: AccountRecoveryPane(),
  );
}

/// The recovery explanation and its one action, embeddable as a Space settings
/// pane as well as routed.
class AccountRecoveryPane extends ConsumerWidget {
  const AccountRecoveryPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final canIssue = ref
        .watch(myPermissionsProvider)
        .hasPermission(Perm.administrator);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Titled because a description only renders under a title.
        SettingsSectionCard(
          title: 'Reset codes',
          description:
              'There is no recovery email. Somebody locked out of their '
              'account gets back in with a one-time code an administrator '
              'issues them, spent through "Trouble signing in?" on the '
              'sign-in screen.',
          children: [
            AppListRow(
              label: 'Issue a reset code',
              leading: const Icon(AppIcons.resetCode),
              meta: canIssue ? null : 'Administrators only',
              semanticLabel: 'Issue a reset code, choose a member',
              trailing: Icon(
                AppIcons.chevronRight,
                size: AppSizes.icon16,
                color: tokens.textSecondary,
              ),
              onTap: canIssue ? () => _pickThenIssue(context) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Chooses a member, then opens the issuing sheet for them.
///
/// Two sheets rather than one screen: the picker and the issuing sheet both
/// already exist and neither knows about the other, so this is the whole of
/// the new path. A cancelled pick closes without issuing anything.
Future<void> _pickThenIssue(BuildContext context) async {
  final member = await showAppSheet<api.UserProfile>(
    context,
    builder: (context) => const MemberPickerSheet(),
  );
  if (member == null || !context.mounted) return;
  await showResetCodeSheet(
    context,
    subjectId: member.id,
    subjectName: member.displayName,
  );
}
