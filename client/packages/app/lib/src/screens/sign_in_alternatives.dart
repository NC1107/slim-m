// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The row of ways out from under the sign-in button.
///
/// Split from `sign_in_screen.dart` when adding recovery pushed that file
/// past the size ceiling. They read as alternatives to the action above
/// rather than a list under it, which is why they share one [Wrap] instead of
/// stacking.
///
/// "Trouble signing in?" is last and only while signing in: it is meaningless
/// on the create-account branch, where there is no account to recover yet.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class SignInAlternatives extends StatelessWidget {
  const SignInAlternatives({
    super.key,
    required this.creatingAccount,
    required this.busy,
    required this.addressExpanded,
    required this.onToggleCreating,
    required this.onExpandAddress,
    required this.onJoinDifferentSpace,
    required this.onRecoverAccount,
  });

  final bool creatingAccount;
  final bool busy;
  final bool addressExpanded;
  final VoidCallback onToggleCreating;
  final VoidCallback onExpandAddress;
  final VoidCallback onJoinDifferentSpace;

  /// Opens the reset-code flow. Absent while creating an account.
  final VoidCallback onRecoverAccount;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: AppSpacing.s8,
    runSpacing: AppSpacing.s4,
    children: [
      AppButton(
        label: creatingAccount
            ? 'I already have an account'
            : 'Create an account instead',
        variant: AppButtonVariant.ghost,
        disabled: busy,
        onPressed: onToggleCreating,
      ),
      if (!addressExpanded)
        AppButton(
          label: 'Use a different server',
          variant: AppButtonVariant.ghost,
          disabled: busy,
          onPressed: onExpandAddress,
        ),
      // Once a Space is remembered this is the only way back to invite redemption.
      AppButton(
        label: 'Join a different Space',
        variant: AppButtonVariant.ghost,
        disabled: busy,
        onPressed: onJoinDifferentSpace,
      ),
      if (!creatingAccount)
        AppButton(
          label: 'Trouble signing in?',
          variant: AppButtonVariant.ghost,
          disabled: busy,
          onPressed: onRecoverAccount,
        ),
    ],
  );
}
