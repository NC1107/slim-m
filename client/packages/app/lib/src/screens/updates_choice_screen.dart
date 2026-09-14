// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one question the join flow asks a desktop install after the account
/// exists: keep slim-m up to date automatically?
///
/// Asked here, once, because the owner wanted it at signup rather than as a
/// dialog that interrupts a working app later. No stepper: this is not a
/// counted step of joining a Space, it is the desktop install's own
/// question, and it never shows on a phone or in a browser, where the store
/// or the page owns updating. The answer is [autoUpdateProvider]; Settings,
/// under About, is where it is changed afterwards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import '../providers/auto_update_preference.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import '../widgets/onboarding_shell.dart';

class UpdatesChoiceScreen extends ConsumerWidget {
  const UpdatesChoiceScreen({super.key, this.format});

  /// Injectable for tests; the real build reads its own install format.
  final InstallFormat? format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final installFormat = format ?? currentInstallFormat();

    Future<void> answer(bool enabled) async {
      await ref.read(autoUpdateProvider.notifier).set(enabled);
      if (context.mounted) context.go(Routes.channels);
    }

    return OnboardingShell(
      version: ref.watch(appInfoProvider).valueOrNull?.version,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Keep slim-m up to date automatically?',
            style: AppText.title.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'When this is on, slim-m looks for a new version each time it '
            'opens and installs it before the app starts.',
            style: AppText.body.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            autoUpdateMechanismNote(installFormat),
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s24),
          AppButton(
            label: 'Turn on automatic updates',
            variant: AppButtonVariant.primary,
            size: AppButtonSize.lg,
            full: true,
            onPressed: () => answer(true),
          ),
          const SizedBox(height: AppSpacing.s12),
          Center(
            child: AppButton(
              label: 'Not now',
              variant: AppButtonVariant.ghost,
              onPressed: () => answer(false),
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          Text(
            'You can change this any time in Settings, under About.',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// What "installs it" actually means for this install, said up front so the
/// dnf password prompt an rpm user will see is expected rather than alarming.
String autoUpdateMechanismNote(InstallFormat format) => switch (format) {
  InstallFormat.rpm =>
    'This install updates through dnf, so your system will ask for your '
        'password when there is one to install.',
  InstallFormat.deb =>
    'This install updates through your package manager, so your system '
        'will ask for your password when there is one to install.',
  InstallFormat.flatpak =>
    'This install updates through flatpak; slim-m will tell you when a '
        'new version is ready and how to get it.',
  InstallFormat.appImage || InstallFormat.tarball || InstallFormat.unknown =>
    'This install cannot replace itself yet; slim-m will tell you when a '
        'new version is ready and open the release for you.',
};
