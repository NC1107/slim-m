// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The three credential inputs on the sign-in form: username, the display name
/// that only a new account is asked for, and password.
///
/// Split out of `sign_in_screen.dart` when stating the username and password
/// rules in helper text took that file past its hard line ceiling. It is the
/// same seam `sign_in_error.dart` already took - a self-contained piece with no
/// state of its own, driven entirely by what it is handed.
///
/// The helpers matter more than they look: the server enforces a charset and
/// two lengths, and before these lines existed the first a newcomer heard of
/// any of it was a rejection after pressing the button.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../widgets/labeled_field.dart';
import 'sign_in_error.dart';

class SignInCredentialFields extends StatelessWidget {
  const SignInCredentialFields({
    super.key,
    required this.username,
    required this.displayName,
    required this.password,
    required this.creatingAccount,
    required this.busy,
    required this.errorFor,
    required this.onSubmit,
  });

  final TextEditingController username;
  final TextEditingController displayName;
  final TextEditingController password;

  /// Whether this is a registration, which is the only time a display name is
  /// asked for.
  final bool creatingAccount;
  final bool busy;

  /// The error currently owned by a given field, or null when it has none.
  final String? Function(SignInErrorField) errorFor;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledField(
          label: 'Username',
          helper: 'Letters, digits, _ . and - only. Up to 32 characters.',
          child: AppInput(
            controller: username,
            errorText: errorFor(SignInErrorField.username),
            autocorrect: false,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            semanticLabel: 'Username',
          ),
        ),
        if (creatingAccount) ...[
          const SizedBox(height: AppSpacing.s16),
          LabeledField(
            label: 'Display name',
            helper: 'What others see. Defaults to your username.',
            child: AppInput(
              controller: displayName,
              textInputAction: TextInputAction.next,
              semanticLabel: 'Display name',
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s16),
        LabeledField(
          label: 'Password',
          helper: 'At least 8 characters.',
          child: AppInput(
            controller: password,
            errorText: errorFor(SignInErrorField.password),
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            semanticLabel: 'Password',
            onSubmitted: (_) => busy ? null : onSubmit(),
          ),
        ),
      ],
    );
  }
}
