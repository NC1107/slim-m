// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Joining: the three ways in.
///
/// Self-hosting is the normal case here, not an advanced option, so choosing a
/// server is the first thing the app asks rather than something buried in
/// settings. The three entry points are the three real situations: you were sent
/// an invite, you run your own server, or you are joining the official one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../default_server.dart';
import '../deep_links.dart';
import '../providers/providers.dart';
import 'onboarding_dialogs.dart';
import '../widgets/onboarding_shell.dart';
import '../widgets/server_identity_confirmation.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({required this.onServerChosen, super.key});

  /// Called once a reachable server has been chosen and, if an invite was used,
  /// verified. Carries the invite so the sign-up step can redeem it.
  final void Function(Uri server, String? inviteCode) onServerChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    // A tapped slimm:// link: open the redeem dialog prefilled post-frame, consuming it so a rebuild does not reopen it; watched so a tap while this screen is up also opens it (see deep_links.dart).
    if (ref.watch(tappedInviteProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final invite = ref.read(tappedInviteProvider);
        if (invite == null || !context.mounted) return;
        ref.read(tappedInviteProvider.notifier).state = null;
        _redeemFlow(context, ref, initial: invite);
      });
    }

    return OnboardingShell(
      step: OnboardingStep.invite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Where are you joining?',
            style: AppText.title.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Chat and voice you host yourself.',
            style: AppText.body.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s24),
          // Staggered a beat apart so the three ways in arrive as a sequence.
          AppFadeIn(
            child: _Entry(
              icon: AppIcons.invite,
              title: 'I have an invite',
              description: 'Someone sent you a code for their Space.',
              onTap: () => _redeemFlow(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppFadeIn(
            delay: const Duration(milliseconds: 45),
            child: _Entry(
              icon: AppIcons.settings,
              title: 'Connect to a Space',
              description: 'You run your own, or you have its address.',
              onTap: () => _manualFlow(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppFadeIn(
            delay: const Duration(milliseconds: 90),
            child: _Entry(
              icon: AppIcons.members,
              title: 'Join the official Space',
              description: officialServer,
              onTap: () => _officialFlow(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  /// The dialog validates and pops before this runs, the same order
  /// [_manualFlow] uses: identity confirmation navigates full-screen, and
  /// that must never happen underneath a still-open dialog.
  Future<void> _redeemFlow(
    BuildContext context,
    WidgetRef ref, {
    ({Uri server, String code})? initial,
  }) async {
    final result = await showAppSheet<(Uri, String)>(
      context,
      builder: (context) => InviteDialog(initial: initial),
    );
    if (result == null || !context.mounted) return;

    final (server, code) = result;
    if (await confirmServerIdentity(context, ref, server)) {
      onServerChosen(server, code);
    }
  }

  Future<void> _manualFlow(BuildContext context, WidgetRef ref) async {
    final server = await showAppSheet<Uri>(
      context,
      builder: (context) => const ManualServerDialog(),
    );
    if (server == null || !context.mounted) return;

    if (await confirmServerIdentity(context, ref, server)) {
      onServerChosen(server, null);
    }
  }

  /// The official address is a compile-time constant, never user input, so
  /// there is nothing to validate here. First connect pins its identity
  /// silently rather than asking someone to read a fingerprint aloud to an
  /// admin that, for this address, does not exist - the app and the server
  /// are published by the same source. A later mismatch still stops the
  /// flow: that would mean this well-known address answered with a
  /// different key than the one already pinned, which is worth a hard stop
  /// regardless of how the address was chosen.
  ///
  /// This screen only ever runs on an install with no server chosen before,
  /// so tapping this button is itself evidence there is no account here yet
  /// - the same reasoning [assumeNewAccountProvider] documents - and sign-in
  /// opens on creating one rather than asking for a tap it does not need.
  Future<void> _officialFlow(BuildContext context, WidgetRef ref) async {
    final server = Uri.parse(officialServer);
    if (await confirmServerIdentity(
      context,
      ref,
      server,
      silentFirstConnect: true,
    )) {
      ref.read(assumeNewAccountProvider.notifier).state = true;
      onServerChosen(server, null);
    }
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      button: true,
      label: '$title. $description',
      child: AppFocusRing(
        radius: AppRadii.card,
        builder: (context, onFocusChange) => InkWell(
          onTap: onTap,
          // AppFocusRing replaces this overlay; see its own doc comment.
          focusColor: Colors.transparent,
          onFocusChange: onFocusChange,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Container(
            // Comfortably past the 48dp minimum target.
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Row(
              children: [
                Icon(icon, color: tokens.accent),
                const SizedBox(width: AppSpacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontWeight: AppWeights.semi,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        description,
                        style: AppText.caption.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Redeeming an invite: check the code against the server before asking anyone
/// to fill in a signup form, and accept the terms at the point of joining.
