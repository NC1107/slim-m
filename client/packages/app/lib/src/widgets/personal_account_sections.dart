// SPDX-License-Identifier: Apache-2.0
/// Three personal settings sections about the account itself: linked
/// devices, blocked users, and sign-out or deletion.
///
/// Account deletion is reachable in two taps from the main surface, which the
/// app stores require and which is also just correct: an account you cannot
/// leave is a trap.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../providers/blocks_controller.dart';
import '../providers/providers.dart';
import '../providers/push_controller.dart';
import '../providers/sync_controller.dart';
import '../providers/user_profiles.dart';
import 'run_guarded.dart';
import 'settings_section_header.dart';

/// The account's devices, refetched when invalidated.
final devicesProvider = FutureProvider.autoDispose<List<api.Device>>(
  (ref) => ref.watch(apiProvider).listDevices(),
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
                      _DeviceRow(key: ValueKey(device.id), device: device),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One signed-in device, with its own "sign out" failure: a revoke that
/// cannot reach the server must say so on the row it was for, not vanish.
class _DeviceRow extends ConsumerStatefulWidget {
  const _DeviceRow({super.key, required this.device});

  final api.Device device;

  @override
  ConsumerState<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends ConsumerState<_DeviceRow>
    with GuardedActionState<_DeviceRow> {
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'sign out that device',
      action: () => ref.read(apiProvider).removeDevice(widget.device.id),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.invalidate(devicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final device = widget.device;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  onPressed: _busy ? null : _signOut,
                  child: const Text('Sign out'),
                ),
        ),
        if (actionError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              0,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            child: AppErrorState(
              message: actionError!,
              onDismiss: clearActionError,
            ),
          ),
      ],
    );
  }
}

/// The blocked list, and the one place a block can be undone.
///
/// Says what blocking really does rather than the old blanket promise: messages,
/// reactions and typing are hidden and no notification arrives, and the person
/// is still in the member list, which is where the row that offers this lives.
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
          description:
              'They are not told. You stop seeing their messages, reactions '
              'and typing, and stop being notified about them. They stay in '
              'the member list. Unblocking restores everything.',
        ),
        if (!blocks.settled)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.s16),
            child: LinearProgressIndicator(),
          )
        else if (blocks.error case final error?)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: AppErrorState(
              message: 'Could not load the block list.',
              detail: error,
              onRetry: () => ref.read(blocksProvider.notifier).refresh(),
            ),
          )
        else if (blocks.ids.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s16,
              vertical: AppSpacing.s8,
            ),
            child: Text(
              'Nobody is blocked.',
              style: TextStyle(color: tokens.textSecondary),
            ),
          )
        else
          Column(
            children: [
              for (final userId in blocks.ids) _BlockedRow(userId: userId),
            ],
          ),
      ],
    );
  }
}

/// One blocked person, by name.
///
/// The id is resolved through the same profile fetch every message author goes
/// through. It used to render the raw 36-character uuid, which reads as
/// corruption rather than as a person somebody chose to block, and gives no way
/// to tell two of them apart.
class _BlockedRow extends ConsumerWidget {
  const _BlockedRow({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(userId));
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // A deleted account resolves to null, and its id is all there is left of it.
    final name =
        profile.valueOrNull?.displayName ?? profile.valueOrNull?.username;

    return ListTile(
      leading: const Icon(AppIcons.account),
      title: Text(name ?? 'Deleted account'),
      subtitle: name == null
          ? Text(userId, style: TextStyle(color: tokens.textSecondary))
          : null,
      trailing: TextButton(
        onPressed: () => _unblock(context, ref),
        child: const Text('Unblock'),
      ),
    );
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(blocksProvider.notifier).unblock(userId);
    } on api.ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeApiFailure('unblock that user', e))),
      );
    }
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
  /// with no idea why nothing updates any more; sync and push, stopped ahead
  /// of the request, are restarted on that same failure for the same reason.
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

    /// Both read before the request, and both restarted without consulting
    /// [mounted]: what they undo is app-global, so navigating away from this
    /// screen while the delete is in flight must not be what leaves sync
    /// stopped and push unregistered for the rest of the process. Only the
    /// error text is this widget's, and only that needs the guard.
    final sync = ref.read(syncControllerProvider.notifier);
    final push = ref.read(pushControllerProvider.notifier);
    await sync.stop();
    await push.unregister();
    try {
      await ref.read(apiProvider).deleteAccount();
    } on api.ApiException catch (e) {
      /// Not on a 401: there the session is already gone, cleared by the
      /// refresh path before this catch runs, so restarting would race the
      /// sign-out into an exponential retry loop against a signed-out
      /// session and register push with no session to bind it to.
      if (e is! api.UnauthorizedException) {
        unawaited(sync.start());
        unawaited(push.register());
      }
      if (!mounted) return;
      setState(() => _deleteError = e.message);
    }
  }
}

/// Signing out, on its own so it can be pinned to the settings nav's footer
/// rather than sitting in a pane.
///
/// It is the one action here that is not about changing a setting, which is why
/// it belongs on the frame: you do not go looking for it inside a category.
/// Deliberately no longer beside "Delete account" - one is routine and the
/// other is irreversible, and a routine action next to a destructive one is
/// how a mis-tap happens.
class SignOutRow extends ConsumerWidget {
  const SignOutRow({super.key});

  /// Push is unregistered before the session goes, or this device keeps waking
  /// for an account that is no longer signed in on it.
  static Future<void> signOut(WidgetRef ref) async {
    await ref.read(syncControllerProvider.notifier).stop();
    await ref.read(pushControllerProvider.notifier).unregister();
    try {
      await ref.read(apiProvider).logout();
    } on api.ApiException {
      // The session may already be gone; clear locally either way.
      ref.read(sessionProvider).clear();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AppListRow(
      label: 'Sign out',
      leading: Icon(
        AppIcons.signOut,
        size: AppSizes.icon16,
        color: tokens.dangerText,
      ),
      onTap: () => signOut(ref),
    );
  }
}
