// SPDX-License-Identifier: Apache-2.0
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

import '../widgets/server_identity_confirmation.dart';

/// The official instance. Someone with no invite and no server of their own
/// still needs somewhere to land.
const officialServer = 'https://slim.npc-server.top';

/// Whether an address is on the loopback interface or a private network.
///
/// These are the ranges where plain http is reasonable: a self-hosted box on a
/// home network cannot get a public certificate for an address that does not
/// resolve publicly, and the traffic never crosses the internet anyway.
bool isLocalAddress(Uri address) {
  final host = address.host;
  if (host == 'localhost' || host.endsWith('.local')) return true;

  final parts = host.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((o) => o == null || o < 0 || o > 255)) return false;

  final [a, b, _, _] = octets.cast<int>();
  // 127/8 loopback, 10/8, 192.168/16, and 172.16/12 private ranges.
  return a == 127 ||
      a == 10 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31);
}

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({required this.onServerChosen, super.key});

  /// Called once a reachable server has been chosen and, if an invite was used,
  /// verified. Carries the invite so the sign-up step can redeem it.
  final void Function(Uri server, String? inviteCode) onServerChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Scaffold(
      // Both edges: this screen has no AppBar, so nothing else clears the
      // notch, and its content runs the full height of the view.
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'slim-m',
                    textAlign: TextAlign.center,
                    style: AppText.heading.copyWith(
                      color: tokens.textPrimary,
                      fontFamily: AppFonts.mono,
                      fontWeight: AppWeights.medium,
                      letterSpacing: 20 * 0.04,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'Where are you joining?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.s32),
                  _Entry(
                    icon: AppIcons.invite,
                    title: 'I have an invite',
                    description: 'Someone sent you a code for their Space.',
                    onTap: () => _redeemFlow(context),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  _Entry(
                    icon: AppIcons.settings,
                    title: 'Connect to a Space',
                    description: 'You run your own, or you have its address.',
                    onTap: () => _manualFlow(context, ref),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  _Entry(
                    icon: AppIcons.members,
                    title: 'Join the official Space',
                    description: officialServer,
                    onTap: () =>
                        onServerChosen(Uri.parse(officialServer), null),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _redeemFlow(BuildContext context) async {
    final result = await showDialog<(Uri, String)>(
      context: context,
      builder: (context) => const _InviteDialog(),
    );
    if (result != null) onServerChosen(result.$1, result.$2);
  }

  Future<void> _manualFlow(BuildContext context, WidgetRef ref) async {
    final server = await showDialog<Uri>(
      context: context,
      builder: (context) => const _ManualServerDialog(),
    );
    if (server == null || !context.mounted) return;

    if (await confirmServerIdentity(context, ref, server)) {
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
      child: InkWell(
        onTap: onTap,
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      description,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
    setState(() {
      _busy = true;
      _error = null;
    });

    final client = api.SlimmApi(baseUrl: address);
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
        Navigator.of(context).pop((address, _code.text.trim()));
      }
    } on api.ApiException catch (e) {
      setState(
        () => _error = e is api.TransportException
            ? 'Could not reach that server.'
            : 'The server refused that. ${e.message}',
      );
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Redeem an invite'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _server,
            decoration: const InputDecoration(
              labelText: 'Server',
              hintText: 'https://chat.example',
            ),
            autocorrect: false,
          ),
          const SizedBox(height: AppSpacing.s16),
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Invite code'),
            autocorrect: false,
          ),
          const SizedBox(height: AppSpacing.s16),
          // Terms are accepted at the point of joining, which is where the
          // decision actually is, not buried in a later settings screen.
          CheckboxListTile(
            value: _accepted,
            onChanged: (v) => setState(() => _accepted = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I accept the terms of use for this Space.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || !_accepted ? null : _verify,
          child: const Text('Continue'),
        ),
      ],
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

    /// Typing a server address by hand is a trust decision, so it is stated
    /// rather than implied: whoever runs it can read everything sent there.
    ///
    /// https is required over the internet, but not on a local network. A box on
    /// your own LAN has no public hostname to get a certificate for, and
    /// refusing http there would make self-hosting, the normal case for this
    /// app, impossible without a pile of certificate work.
    if (address.scheme != 'https' && !isLocalAddress(address)) {
      setState(
        () => _error =
            'Use https for a server on the internet, so '
            'traffic cannot be read in transit. Plain http is only accepted for '
            'an address on your own network.',
      );
      return;
    }
    Navigator.of(context).pop(address);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to a Space'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _server,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: 'https://chat.example',
            ),
            autocorrect: false,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.s16),
          Text(
            'Whoever runs this Space can read the messages sent through it. '
            'Only connect to one you trust.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).extension<AppTokens>()!.textSecondary,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
