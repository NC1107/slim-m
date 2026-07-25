// SPDX-License-Identifier: Apache-2.0
/// Account settings: devices, blocked users, sign out, and deletion.
///
/// Account deletion is reachable in two taps from the main surface, which the
/// app stores require and which is also just correct: an account you cannot
/// leave is a trap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/push_controller.dart';
import '../providers/sync_controller.dart';

/// The account's devices, refetched when invalidated.
final devicesProvider = FutureProvider.autoDispose<List<api.Device>>(
  (ref) => ref.watch(apiProvider).listDevices(),
);

/// The users this account has blocked.
final blocksProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(apiProvider).listBlocks(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          _DevicesSection(),
          Divider(height: 1),
          _BlockedSection(),
          Divider(height: 1),
          _AccountSection(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s24,
        AppSpacing.s16,
        AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              description!,
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _DevicesSection extends ConsumerWidget {
  const _DevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          'Devices',
          description: 'Everywhere this account is signed in.',
        ),
        devices.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('Could not load devices. $e'),
          ),
          data: (list) => Column(
            children: [
              for (final device in list)
                ListTile(
                  leading: const Icon(AppIcons.account),
                  title: Text(device.name),
                  subtitle: Text(
                    device.isCurrent ? 'This device' : 'Signed in',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                  trailing: device.isCurrent
                      ? null
                      : TextButton(
                          onPressed: () async {
                            await ref.read(apiProvider).removeDevice(device.id);
                            ref.invalidate(devicesProvider);
                          },
                          child: const Text('Sign out'),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BlockedSection extends ConsumerWidget {
  const _BlockedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(blocksProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          'Blocked',
          description:
              'They are not told, and unblocking restores their messages.',
        ),
        blocks.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('Could not load the block list. $e'),
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s16,
                    vertical: AppSpacing.s8,
                  ),
                  child: Text(
                    'Nobody is blocked.',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                )
              : Column(
                  children: [
                    for (final userId in list)
                      ListTile(
                        title: Text(userId),
                        trailing: TextButton(
                          onPressed: () async {
                            await ref.read(apiProvider).unblockUser(userId);
                            ref.invalidate(blocksProvider);
                          },
                          child: const Text('Unblock'),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Account'),
        ListTile(
          leading: const Icon(AppIcons.signOut),
          title: const Text('Sign out'),
          onTap: () async {
            await ref.read(syncControllerProvider.notifier).stop();
            // Drop the push registration first, while the session that owns it
            // is still valid. Otherwise this handset keeps waking for an
            // account nobody is signed into, which on a shared or handed-on
            // device means notifying the wrong person.
            await ref.read(pushControllerProvider).unregister();
            try {
              await ref.read(apiProvider).logout();
            } on api.ApiException {
              // The session may already be gone; either way this device is done
              // with it, so clear locally rather than stranding the user here.
              ref.read(sessionProvider).clear();
            }
          },
        ),
        ListTile(
          leading: Icon(
            AppIcons.failed,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Delete account',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          subtitle: const Text('Permanent. This cannot be undone.'),
          onTap: () => _confirmDeletion(context, ref),
        ),
      ],
    );
  }

  /// Deletion is irreversible, so it asks plainly and states what survives.
  /// Saying "your messages stay" up front is more honest than a vague warning,
  /// and it is the thing people are actually surprised by afterwards.
  Future<void> _confirmDeletion(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this account?'),
        content: const Text(
          'Your devices, read state, and blocks are erased, and the username '
          'becomes available again.\n\n'
          'Messages you posted in shared channels stay, so conversations do not '
          'develop holes, but they will no longer be attributed to you.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(syncControllerProvider.notifier).stop();
    await ref.read(apiProvider).deleteAccount();
  }
}
