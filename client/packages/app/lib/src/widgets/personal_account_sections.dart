// SPDX-License-Identifier: Apache-2.0
/// Three personal settings sections about the account itself: linked
/// devices, blocked users, and sign-out or deletion.
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
import 'settings_section_header.dart';

/// The account's devices, refetched when invalidated.
final devicesProvider = FutureProvider.autoDispose<List<api.Device>>(
  (ref) => ref.watch(apiProvider).listDevices(),
);

/// The users this account has blocked.
final blocksProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(apiProvider).listBlocks(),
);

class DevicesSection extends ConsumerWidget {
  const DevicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Devices'),
        devices.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('Could not load devices.'),
          ),
          // Named like Blocked's empty state below: a bare section header
          // over nothing reads as a loading glitch, not an intentional state.
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Text(
                    'No devices signed in.',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                )
              : Column(
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
                                  await ref
                                      .read(apiProvider)
                                      .removeDevice(device.id);
                                  if (context.mounted) {
                                    ref.invalidate(devicesProvider);
                                  }
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

class BlockedSection extends ConsumerWidget {
  const BlockedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(blocksProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          'Blocked',
          description: 'They are not told. Unblocking restores their messages.',
        ),
        blocks.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('Could not load the block list.'),
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
                            if (context.mounted) ref.invalidate(blocksProvider);
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

class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  /// A failed deletion stays on screen until it is retried or dismissed: it
  /// is the most consequential action here, and a toast that floats away
  /// leaves the user with no idea why nothing changed.
  String? _deleteError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Account'),
        ListTile(
          leading: const Icon(AppIcons.signOut),
          title: const Text('Sign out'),
          onTap: () async {
            await ref.read(syncControllerProvider.notifier).stop();
            // Before the session goes, or this device keeps waking for nobody.
            await ref.read(pushControllerProvider.notifier).unregister();
            try {
              await ref.read(apiProvider).logout();
            } on api.ApiException {
              // The session may already be gone; clear locally either way.
              ref.read(sessionProvider).clear();
            }
          },
        ),
        ListTile(
          leading: Icon(
            AppIcons.failed,
            color: Theme.of(context).extension<AppTokens>()!.dangerText,
          ),
          title: Text(
            'Delete account',
            style: TextStyle(
              color: Theme.of(context).extension<AppTokens>()!.dangerText,
            ),
          ),
          subtitle: const Text('Permanent. This cannot be undone.'),
          onTap: () => _confirmDeletion(context, ref),
        ),
        if (_deleteError case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              0,
              AppSpacing.s16,
              AppSpacing.s16,
            ),
            child: AppErrorState(
              message:
                  'Could not delete the account. Your account is '
                  'unchanged and you are still signed in.',
              detail: error,
              onRetry: () => _confirmDeletion(context, ref),
              onDismiss: () => setState(() => _deleteError = null),
            ),
          ),
      ],
    );
  }

  /// Deletion is irreversible, so it asks plainly and states what survives.
  /// Saying "your messages stay" up front is more honest than a vague warning,
  /// and it is the thing people are actually surprised by afterwards.
  ///
  /// Push is unregistered before the delete for the same reason sign-out does
  /// it: the device's push key has to go while the session that registered it
  /// is still valid, so it is not left to be inherited by whichever account
  /// signs into this device next.
  ///
  /// A failed delete deliberately leaves the session alone. Unlike sign-out,
  /// deletion is not safe to assume happened just because the request failed,
  /// and clearing it would orphan the account with no session left to retry
  /// from. The failure still has to reach the screen, or the user is stranded
  /// with no idea why nothing updates any more.
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
              backgroundColor: Theme.of(
                context,
              ).extension<AppTokens>()!.dangerText,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(syncControllerProvider.notifier).stop();
    await ref.read(pushControllerProvider.notifier).unregister();
    try {
      await ref.read(apiProvider).deleteAccount();
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleteError = e.message);
    }
  }
}
