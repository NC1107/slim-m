// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Two-factor authentication, under Account & devices: turn it on, replace the
/// recovery codes, turn it off.
///
/// Absent entirely when the operator has set the policy to `off` and the member
/// has no factor, for the reason `AppLockSection` hides itself off
/// `supportsBiometricLock`: a control that can do nothing is worse than no
/// control. A member who *does* have one still sees the section, because `off`
/// deliberately keeps enforcing an existing factor and turning it off has to
/// stay possible (decision 0048).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import 'settings_notice.dart';
import 'settings_section_header.dart';
import 'totp_code_sheet.dart';
import 'totp_enrol_sheet.dart';
import 'totp_recovery_codes.dart';

final totpStatusProvider = FutureProvider.autoDispose<api.TotpStatus>(
  (ref) => ref.watch(apiProvider).totpStatus(),
);

/// Below this, the section says so rather than only showing the number: a
/// count nobody reads as low is not a warning.
const _lowRecoveryCodes = 3;

class TotpSection extends ConsumerWidget {
  const TotpSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(totpStatusProvider);
    return status.when(
      loading: () => const SettingsSectionCard(
        title: 'Two-factor authentication',
        children: [AppListRow(label: 'Loading…')],
      ),
      // A fixed sentence, never the exception itself; see `JoinPolicyRow`.
      error: (e, _) => SettingsSectionCard(
        title: 'Two-factor authentication',
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s8),
            child: AppErrorState(
              message: 'Could not load your two-factor settings.',
              onRetry: () => ref.invalidate(totpStatusProvider),
            ),
          ),
        ],
      ),
      data: (loaded) => _TotpBody(status: loaded),
    );
  }
}

class _TotpBody extends ConsumerWidget {
  const _TotpBody({required this.status});

  final api.TotpStatus status;

  bool get _hidden =>
      status.policy == api.TotpPolicy.off && !status.enabled && !status.pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_hidden) return const SizedBox.shrink();
    return SettingsSectionCard(
      title: 'Two-factor authentication',
      description: _description,
      children: status.enabled
          ? [
              if (status.recoveryCodesRemaining <= _lowRecoveryCodes)
                _LowCodesNotice(remaining: status.recoveryCodesRemaining),
              _RecoveryCodesRow(remaining: status.recoveryCodesRemaining),
              const _DisableRow(),
            ]
          : [_TurnOnRow(pending: status.pending)],
    );
  }

  String get _description {
    if (status.enabled) {
      return 'Signing in on a new device asks for a code from your '
          'authenticator app as well as your password.';
    }
    if (status.policy == api.TotpPolicy.requiredForElevated) {
      return 'A code from an authenticator app, as well as your password. '
          'This server expects it of anyone who can moderate or administer '
          'it, so a leaked password alone is not enough to take over.';
    }
    return 'A code from an authenticator app, as well as your password, when '
        'you sign in on a new device. Nothing changes until you have proved '
        'a code works, so you cannot lock yourself out setting it up.';
  }
}

class _TurnOnRow extends ConsumerWidget {
  const _TurnOnRow({required this.pending});

  /// An enrolment was started and never confirmed. Worth saying, because the
  /// offer is "finish this" rather than "start something".
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppListRow(
    label: pending ? 'Finish setting up' : 'Turn on two-factor authentication',
    leading: const Icon(AppIcons.shield),
    subtitle: pending
        ? 'You started setting this up and did not finish, so it is not on '
              'yet. Starting again gives you a fresh key.'
        : null,
    onTap: () async {
      final done = await showTotpEnrolSheet(context);
      if (done == true) ref.invalidate(totpStatusProvider);
    },
  );
}

class _RecoveryCodesRow extends ConsumerWidget {
  const _RecoveryCodesRow({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppListRow(
    label: 'Recovery codes',
    leading: const Icon(AppIcons.resetCode),
    meta: '$remaining left',
    semanticLabel: 'Recovery codes, $remaining left',
    onTap: () => _reissue(context, ref),
  );

  /// Replacing the set needs a current code, and the sheet that asks for one
  /// hands back the new codes through a second sheet rather than a toast: they
  /// are shown once, so they need somewhere they can be read and copied.
  Future<void> _reissue(BuildContext context, WidgetRef ref) async {
    List<String>? fresh;
    await showTotpCodeSheet(
      context,
      title: 'New recovery codes',
      description:
          'Enter a code from your authenticator, or one of your current '
          'recovery codes. The codes you have now will stop working.',
      submitLabel: 'Replace codes',
      onSubmit: (code) async {
        try {
          fresh = await ref.read(apiProvider).reissueTotpRecoveryCodes(code);
          return null;
        } on api.ApiException catch (e) {
          return totpCodeFailure(e);
        }
      },
    );
    final codes = fresh;
    if (codes == null || !context.mounted) return;
    ref.invalidate(totpStatusProvider);
    await showAppSheet<void>(
      context,
      builder: (context) => TotpRecoveryCodesView(
        codes: codes,
        headline: 'Your new recovery codes',
        onDone: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _DisableRow extends ConsumerWidget {
  const _DisableRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppListRow(
    label: 'Turn off two-factor authentication',
    leading: const Icon(AppIcons.shieldOff),
    // Short enough to survive a row's one-line truncation on a phone.
    subtitle: 'Your password alone will get you back in.',
    onTap: () async {
      final done = await showTotpCodeSheet(
        context,
        title: 'Turn off two-factor authentication',
        description:
            'Enter a code from your authenticator, or one of your recovery '
            'codes if you no longer have that phone.',
        submitLabel: 'Turn off',
        dangerous: true,
        onSubmit: (code) async {
          try {
            await ref.read(apiProvider).disableTotp(code);
            return null;
          } on api.ApiException catch (e) {
            return totpCodeFailure(e);
          }
        },
      );
      if (done == true) ref.invalidate(totpStatusProvider);
    },
  );
}

class _LowCodesNotice extends StatelessWidget {
  const _LowCodesNotice({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) => SettingsNotice(
    message: remaining == 0
        ? 'You have no recovery codes left. Without one, losing your '
              'authenticator means asking an administrator to turn this off '
              'for you. Replace them below.'
        : 'Only $remaining recovery code${remaining == 1 ? '' : 's'} left. '
              'Replace them below while you still can.',
  );
}

/// One sentence per failure, shared by every place that submits a code.
///
/// A wrong code is the ordinary case and says what to check; a lockout is told
/// plainly rather than disguised as a wrong code, because a member seeing "that
/// code is wrong" for a correct one concludes their authenticator is broken.
String totpCodeFailure(api.ApiException e) => switch (e) {
  api.BadRequestException() =>
    'That code was not accepted. Codes change every 30 seconds, so check your '
        'phone is showing the current one.',
  api.RateLimitedException() =>
    'Too many incorrect codes. Wait a few minutes and try again.',
  _ => e.message,
};
