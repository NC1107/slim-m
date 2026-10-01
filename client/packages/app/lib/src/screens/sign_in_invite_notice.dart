// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What the create-account form says about invites.
///
/// Split from `sign_in_screen.dart` for its size ceiling. `/version` reports
/// `invite_required` for a brand-new, unclaimed deployment as well as a closed
/// one, so the wording is true of both. Nothing is shown once a code is held
/// this session: telling someone to go and redeem one right after they did is
/// the contradiction this widget exists to avoid.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../widgets/server_notice.dart';

class InviteRequiredNotice extends ConsumerWidget {
  const InviteRequiredNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(pendingInviteProvider) != null) {
      return const SizedBox.shrink();
    }
    return const ServerNotice(
      icon: AppIcons.invite,
      message:
          'Joining needs an invite code once a Space has members. '
          'If this one is brand new, the first account you create '
          'becomes its admin. Otherwise ask a member for a code, '
          'then use "Use a different Space" below to redeem it. '
          'An admin can open joining to anyone in Settings, under Space.',
    );
  }
}
