// SPDX-License-Identifier: Apache-2.0
/// Settings, in three groups: "Personal" is what the account holder controls
/// about themselves, "Space" is what they control about the deployment, and
/// "App" is the build itself, which belongs to neither.
///
/// The split is the whole point of the layout. Presence and appearance follow
/// the person to every Space they sign into; roles and invites belong to this
/// one, and most members cannot touch them at all.
///
/// "App" is last and always present, because the Space group is hidden from a
/// caller holding none of its permission bits: anything after it would
/// otherwise read as part of whichever group did render.
///
/// Account deletion is reachable in two taps from the main surface, which the
/// app stores require and which is also just correct: an account you cannot
/// leave is a trap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../diagnostics/debug_log.dart';
import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import '../providers/push_controller.dart';
import '../providers/sync_controller.dart';
import '../routing/routes.dart';
import '../widgets/appearance_settings_section.dart';
import '../widgets/avatar_settings_section.dart';
import '../widgets/settings_section_header.dart';
import '../widgets/settings_select_row.dart';
import '../widgets/space_settings_section.dart';

/// The account's devices, refetched when invalidated.
final devicesProvider = FutureProvider.autoDispose<List<api.Device>>(
  (ref) => ref.watch(apiProvider).listDevices(),
);

/// The users this account has blocked.
final blocksProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(apiProvider).listBlocks(),
);

/// This build's version and build number, for a tester to read off the
/// screen rather than guessing which build they are running.
final appInfoProvider = FutureProvider.autoDispose<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        // Settings is reached with go(), which replaces rather than pushes, so
        // there is no stack to pop and the implicit back arrow never appears.
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          tooltip: 'Back to channels',
          onPressed: () => context.go(Routes.channels),
        ),
      ),
      body: ListView(
        children: const [
          SettingsGroupHeader('Personal'),
          AvatarSettingsSection(),
          Divider(height: 1),
          AppearanceSettingsSection(),
          Divider(height: 1),
          _PresenceSection(),
          Divider(height: 1),
          _NotificationsSection(),
          Divider(height: 1),
          _VoiceSection(),
          Divider(height: 1),
          _DevicesSection(),
          Divider(height: 1),
          _BlockedSection(),
          Divider(height: 1),
          _AccountSection(),
          SpaceSettingsSection(),
          _AppSection(),
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
        const SettingsSectionHeader('Devices'),
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

/// Whether this device is registered for push, read plainly off the state
/// [PushController] tracks: this is what makes a registration problem
/// diagnosable from the device itself, instead of guessing from server logs.
class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushControllerProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final registered = status == PushStatus.registered;
    final blocked = status == PushStatus.registeredNotificationsBlocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Notifications'),
        ListTile(
          leading: Icon(
            registered ? AppIcons.notificationsOn : AppIcons.notificationsOff,
            color: registered
                ? tokens.accent
                : blocked
                ? Theme.of(context).colorScheme.error
                : tokens.textSecondary,
          ),
          title: Text(status.label),
        ),
      ],
    );
  }
}

/// Voice call preferences: microphone, screen share quality, and sounds.
/// A separate screen rather than inline rows, matching how much is on it.
class _VoiceSection extends StatelessWidget {
  const _VoiceSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Voice'),
        ListTile(
          leading: const Icon(AppIcons.mic),
          title: const Text('Microphone, screen share, sounds'),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => context.push(Routes.voiceSettings),
        ),
      ],
    );
  }
}

/// Sets the caller's own visibility preference via `PATCH /presence`. See
/// [presenceVisibilityDisplayProvider] for why the selected segment is a
/// local echo of the last choice rather than a value read back from the
/// server: there is no endpoint that returns it.
class _PresenceSection extends ConsumerWidget {
  const _PresenceSection();

  static const _options = [
    (api.PresenceVisibility.online, 'Online'),
    (api.PresenceVisibility.away, 'Away'),
    (api.PresenceVisibility.dnd, 'Do not disturb'),
    (api.PresenceVisibility.hidden, 'Appear offline'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(presenceVisibilityDisplayProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Presence'),
        SettingsSelectRow<api.PresenceVisibility>(
          label: 'Status',
          sheetTitle: 'Presence',
          value: selected ?? _options.first.$1,
          choices: [
            for (final option in _options)
              SettingsChoice(value: option.$1, label: option.$2),
          ],
          onChanged: (visibility) async {
            ref.read(presenceVisibilityDisplayProvider.notifier).state =
                visibility;
            try {
              await ref.read(apiProvider).setPresenceVisibility(visibility);
            } on api.ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not update presence. ${e.message}'),
                ),
              );
            }
          },
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

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Account'),
        ListTile(
          leading: const Icon(AppIcons.signOut),
          title: const Text('Sign out'),
          onTap: () async {
            await ref.read(syncControllerProvider.notifier).stop();
            // First, while the session owning it is still valid: otherwise this
            // handset keeps waking for an account nobody is signed into.
            await ref.read(pushControllerProvider.notifier).unregister();
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
    await ref.read(pushControllerProvider.notifier).unregister();
    try {
      await ref.read(apiProvider).deleteAccount();
    } on api.ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the account. ${e.message}')),
      );
    }
  }
}

/// Which build this is, for a tester to read off the device rather than
/// asking whoever is looking at it what they have installed.
///
/// Its own group, not the tail of Personal or of Space. The build number is
/// about the app: it is the same for a member and for an administrator, and
/// it followed whichever group happened to render last while it sat under
/// neither header of its own.
///
/// It owns its leading divider and group header the way
/// [SpaceSettingsSection] does, so the group above it cannot change what this
/// one is called by being absent.
class _AppSection extends ConsumerWidget {
  const _AppSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);
    final errors = ref.watch(debugLogProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SettingsGroupHeader('App'),
        const SizedBox(height: AppSpacing.s8),
        ListTile(
          leading: const Icon(AppIcons.info),
          title: const Text('Version'),
          subtitle: Text(
            info.when(
              data: (i) => '${i.version} (${i.buildNumber})',
              loading: () => 'Loading…',
              error: (e, _) => 'Unknown',
            ),
            style: TextStyle(color: tokens.textSecondary),
          ),
        ),
        ListTile(
          leading: const Icon(AppIcons.info),
          title: const Text('Debug log'),
          subtitle: Text(
            errors.isEmpty
                ? 'Nothing caught this session'
                : '${errors.length} caught this session',
            style: TextStyle(color: tokens.textSecondary),
          ),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => context.push(Routes.debugLog),
        ),
      ],
    );
  }
}
