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
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../default_server.dart';
import '../providers/providers.dart';
import '../server_address_reduction.dart';
import '../server_scheme_policy.dart';
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
  Future<void> _redeemFlow(BuildContext context, WidgetRef ref) async {
    final result = await showAppSheet<(Uri, String)>(
      context,
      builder: (context) => const _InviteDialog(),
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
      builder: (context) => const _ManualServerDialog(),
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
class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog();

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  final _server = TextEditingController();
  final _code = TextEditingController();
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final address = Uri.tryParse(_server.text.trim());
    if (address == null || !address.hasScheme || address.host.isEmpty) {
      setState(() => _error = 'That does not look like a server address.');
      return;
    }
    if (requireSecureScheme(address) case final schemeError?) {
      setState(() => _error = schemeError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    // Userinfo must never ride along on the probe or persist; see reduceServerAddress.
    final reduced = reduceServerAddress(address);
    // The same probe seam confirmServerIdentity uses, so a test can fake the
    // transport for this untrusted address the same way it does for that.
    final client = ref.read(probeApiProvider)(reduced);
    try {
      final check = await client.checkInvite(_code.text.trim());
      if (check is api.InviteUnusable) {
        /// Deliberately vague, and it has to stay that way: the server answers
        /// expired, spent, revoked and never-issued identically so codes cannot
        /// be mined, and naming a reason here would undo that from the client
        /// side by telling an attacker which of the four they hit.
        setState(
          () => _error =
              'That code is not usable. It may have expired '
              'or already been used.',
        );
        return;
      }
      if (mounted) {
        Navigator.of(context).pop((reduced, _code.text.trim()));
      }
    } on api.ApiException catch (e) {
      setState(
        () => _error = e is api.TransportException
            ? 'Could not reach that server.'
            : 'The server refused that. ${sentenceCase(e.message)}',
      );
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Redeem an invite',
            style: AppText.body.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppInput(
            controller: _server,
            placeholder: 'https://chat.example',
            keyboardType: TextInputType.url,
            semanticLabel: 'Server',
          ),
          const SizedBox(height: AppSpacing.s12),
          AppInput(
            controller: _code,
            placeholder: 'Invite code',
            semanticLabel: 'Invite code',
          ),
          const SizedBox(height: AppSpacing.s12),
          // Terms are accepted at the point of joining, which is where the
          // decision actually is, not buried in a later settings screen.
          CheckboxListTile(
            value: _accepted,
            onChanged: (v) => setState(() => _accepted = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'I accept the terms of use for this Space.',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s4),
            AppErrorState(message: _error!),
          ],
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppButton(
                  label: _busy ? 'Checking...' : 'Continue',
                  variant: AppButtonVariant.primary,
                  disabled: _busy || !_accepted,
                  onPressed: _verify,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Connecting to a server by address, with an explicit confirmation step.
class _ManualServerDialog extends StatefulWidget {
  const _ManualServerDialog();

  @override
  State<_ManualServerDialog> createState() => _ManualServerDialogState();
}

class _ManualServerDialogState extends State<_ManualServerDialog> {
  final _server = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  void _submit() {
    final address = Uri.tryParse(_server.text.trim());
    if (address == null || !address.hasScheme || address.host.isEmpty) {
      setState(() => _error = 'That does not look like a server address.');
      return;
    }

    // See requireSecureScheme for why a LAN address is exempt from this.
    if (requireSecureScheme(address) case final schemeError?) {
      setState(() => _error = schemeError);
      return;
    }
    // Userinfo must never survive into storage; see reduceServerAddress.
    Navigator.of(context).pop(reduceServerAddress(address));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect to a Space',
            style: AppText.body.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppInput(
            controller: _server,
            placeholder: 'https://chat.example',
            autofocus: true,
            keyboardType: TextInputType.url,
            semanticLabel: 'Server address',
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Whoever runs this Space can read the messages sent through it. '
            'Only connect to one you trust.',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            AppErrorState(message: _error!),
          ],
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppButton(
                  label: 'Continue',
                  variant: AppButtonVariant.primary,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
