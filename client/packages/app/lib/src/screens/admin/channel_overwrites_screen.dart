// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Per-channel permission overwrites: `GET`/`PUT`/`DELETE
/// /channels/{channelId}/overwrites[/{kind}/{id}]`. Requires MANAGE_ROLES in
/// the target channel.
///
/// A submit always replaces the whole overwrite rather than patching one
/// bit, so [CurrentOverwritesSection] fetches what is already set and both
/// it and [_pickTarget] pre-fill the editor from that instead of opening
/// every target at "Inherit" sight unseen - see `channelOverwritesProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart' show Channel;
import 'package:slimm_design_system/design_system.dart';

import '../../permissions.dart';
import '../../providers/admin_providers.dart';
import '../../providers/channel_permissions.dart';
import '../../providers/providers.dart';
import '../../providers/toasts.dart';
import '../../routing/routes.dart';
import '../settings_screen_scaffold.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_section_header.dart';
import 'current_overwrites_section.dart';
import 'overwrite_target_picker_sheets.dart';
import 'permission_overwrite_row.dart';

class ChannelOverwritesScreen extends StatelessWidget {
  const ChannelOverwritesScreen({super.key, this.initialChannel});

  /// Pre-selects a channel when opened from that channel's own context menu,
  /// skipping the picker; null when reached from Space settings, where the
  /// picker is the point.
  final Channel? initialChannel;

  @override
  Widget build(BuildContext context) => SettingsScreenScaffold(
    title: 'Channel permissions',
    backTooltip: 'Back to Space settings',
    backFallback: Routes.spaceSettings,
    child: ChannelOverwritesPane(initialChannel: initialChannel),
  );
}

/// The overwrite editor itself, embeddable as a Space settings pane as well
/// as routed.
class ChannelOverwritesPane extends ConsumerStatefulWidget {
  const ChannelOverwritesPane({
    super.key,
    this.initialChannel,
    this.lockChannel = false,
  }) : assert(
         !lockChannel || initialChannel != null,
         'lockChannel requires an initialChannel',
       );

  final Channel? initialChannel;

  /// True when embedded in a specific channel's own "Channel settings"
  /// screen, where the channel is fixed by context and a "change channel"
  /// row would contradict the screen it sits in. False (the default) keeps
  /// the picker for the Space settings entry point, where choosing a
  /// channel is the point.
  final bool lockChannel;

  @override
  ConsumerState<ChannelOverwritesPane> createState() =>
      _ChannelOverwritesPaneState();
}

class _ChannelOverwritesPaneState extends ConsumerState<ChannelOverwritesPane>
    with GuardedActionState<ChannelOverwritesPane> {
  Channel? _channel;
  api.OverwriteTarget _kind = api.OverwriteTarget.role;

  @override
  void initState() {
    super.initState();
    _channel = widget.initialChannel;
  }

  String? _targetId;
  String? _targetLabel;
  final Map<int, OverwriteState> _state = {
    for (final p in Perm.channelOverwriteEditable) p.$1: OverwriteState.inherit,
  };
  bool _busy = false;

  void _resetTarget() {
    _targetId = null;
    _targetLabel = null;
    _resetState();
  }

  void _resetState() => _state.updateAll((_, __) => OverwriteState.inherit);

  /// Sets each permission's tri-state from [overwrite]'s allow/deny pair, or
  /// back to "Inherit" for every bit when null - the shared tail of picking a
  /// target, whichever of the two ways this screen offers to pick one.
  void _applyOverwrite(api.ChannelOverwrite? overwrite) {
    _state.updateAll((bit, _) {
      if (overwrite == null) return OverwriteState.inherit;
      if (overwrite.allow & bit != 0) return OverwriteState.allow;
      if (overwrite.deny & bit != 0) return OverwriteState.deny;
      return OverwriteState.inherit;
    });
  }

  /// The already-set overwrite matching [kind]/[id], from whatever
  /// [channelOverwritesProvider] currently holds for [_channel] - null while
  /// it is still loading, has failed, or simply has nothing for this target.
  api.ChannelOverwrite? _existingOverwrite(
    api.OverwriteTarget kind,
    String id,
  ) => ref
      .read(channelOverwritesProvider(_channel!.id))
      .valueOrNull
      ?.where((o) => o.kind == kind && o.id == id)
      .firstOrNull;

  /// Selects a target through [CurrentOverwritesSection] rather than
  /// [_pickTarget]'s pickers: the row itself already carries the overwrite,
  /// so this pre-fills straight from it instead of looking it up again.
  void _selectExisting(api.ChannelOverwrite overwrite, String label) {
    setState(() {
      _kind = overwrite.kind;
      _targetId = overwrite.id;
      _targetLabel = label;
      _applyOverwrite(overwrite);
    });
  }

  Future<void> _pickChannel() async {
    final store = await ref.read(storeProvider.future);
    final channels = await store.watchChannels().first;
    if (!mounted) return;
    final picked = await showAppSheet<Channel>(
      context,
      builder: (context) => ChannelPickerSheet(channels: channels),
    );
    if (picked == null) return;
    setState(() {
      _channel = picked;
      _resetTarget();
    });
  }

  Future<void> _pickTarget() async {
    if (_kind == api.OverwriteTarget.role) {
      final picked = await showAppSheet<api.Role>(
        context,
        builder: (context) => const RolePickerSheet(),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _targetId = picked.id;
        _targetLabel = picked.name;
        _applyOverwrite(_existingOverwrite(_kind, picked.id));
      });
    } else {
      final picked = await showAppSheet<api.UserProfile>(
        context,
        builder: (context) => const MemberPickerSheet(),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _targetId = picked.id;
        _targetLabel = picked.displayName;
        _applyOverwrite(_existingOverwrite(_kind, picked.id));
      });
    }
  }

  /// Submitting can be refused for a permission left at Inherit, which is the
  /// default and is never dimmed, so nothing on screen suggests it carries a
  /// cost.
  ///
  /// The server's escalation check is `granted = allow.remove(old_allow)
  /// .union(old_deny.remove(deny))`, and it requires the caller's own
  /// permissions to contain that. The second half is the trap: if the target
  /// already carries a bit *denied* by a prior overwrite, resubmitting with it
  /// at Inherit rather than Deny un-denies it, and un-denying counts as
  /// granting exactly as Allow does. [_pickTarget] and
  /// [CurrentOverwritesSection] pre-fill Deny for exactly that bit once
  /// `channelOverwritesProvider` has resolved, but a target picked while that
  /// fetch is still loading or has failed still opens at Inherit
  /// indistinguishably from "nothing was ever set here." A caller who does
  /// not hold that bit at their own base level has the whole call refused
  /// with a generic 403. `PermissionOverwriteRow`'s own doc says Deny
  /// "carries no such check and is always offered" and said nothing about
  /// Inherit's identical implicit cost; Clear (see [_clear]) has the same
  /// exposure.
  Future<void> _set() async {
    var allow = 0;
    var deny = 0;
    for (final entry in _state.entries) {
      switch (entry.value) {
        case OverwriteState.allow:
          allow |= entry.key;
        case OverwriteState.deny:
          deny |= entry.key;
        case OverwriteState.inherit:
          break;
      }
    }
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Replace this overwrite?',
      message:
          'This replaces the whole overwrite for $_targetLabel in '
          '"${_channel!.name}": any permission left at "Inherit" above goes '
          'back to inheriting from their roles, even if it was allowed or '
          'denied before.',
      confirmLabel: 'Set overwrite',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'set the overwrite',
      action: () => ref
          .read(apiProvider)
          .setChannelOverwrite(
            channelId: _channel!.id,
            kind: _kind,
            id: _targetId!,
            allow: allow,
            deny: deny,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref
          .read(toastsProvider.notifier)
          .show(
            'Overwrite set for $_targetLabel.',
            severity: AppToastSeverity.success,
          );
    }
  }

  Future<void> _clear() async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Clear this overwrite?',
      message:
          'Every permission for $_targetLabel in "${_channel!.name}" '
          'goes back to inheriting from their roles. This cannot be undone.',
      confirmLabel: 'Clear',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'clear the overwrite',
      action: () => ref
          .read(apiProvider)
          .deleteChannelOverwrite(
            channelId: _channel!.id,
            kind: _kind,
            id: _targetId!,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      setState(_resetState);
      // States the result the idempotent DELETE guarantees, not a "cleared" this screen can never know happened.
      ref
          .read(toastsProvider.notifier)
          .show(
            '$_targetLabel now inherits every permission in '
            '"${_channel!.name}" from their roles.',
            severity: AppToastSeverity.success,
          );
    }
  }

  /// The server checks "allow" against the caller's effective permissions in
  /// the channel actually picked, which a per-channel overwrite of the
  /// caller's own can raise above their base set - so this reads
  /// [myChannelPermissionsProvider] for that channel rather than `/me`'s
  /// base set, closing the gap the old doc comment here used to name before
  /// `GET /channels/{channelId}/permissions` existed. See
  /// docs/decisions/0011-per-channel-permissions.md. Zero (nothing enabled)
  /// before a channel is chosen, since there is nothing to check yet.
  @override
  Widget build(BuildContext context) {
    final myPermissions = _channel != null
        ? ref.watch(myChannelPermissionsProvider(_channel!.id))
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppCallout(
          tone: AppCalloutTone.info,
          child: Text(
            'Picking a target pre-fills what it already has set. Setting an '
            'overwrite still replaces every permission at once, including '
            'any left at "Inherit".',
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        // Inherit and Clear read as always-safe and are not; see _set's doc.
        const AppCallout(
          tone: AppCalloutTone.warn,
          child: Text(
            'A change can still be refused: un-denying a permission counts '
            'as granting it, so if you do not hold that permission '
            'yourself, the whole change comes back refused.',
          ),
        ),
        if (!widget.lockChannel)
          SettingsSectionCard(
            title: 'Channel',
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppListRow(
                label: _channel?.name ?? 'Choose a channel',
                trailing: const Icon(
                  AppIcons.chevronRight,
                  size: AppSizes.icon16,
                ),
                onTap: _pickChannel,
              ),
            ],
          ),
        if (_channel != null) ...[
          const SizedBox(height: AppSpacing.s12),
          CurrentOverwritesSection(
            channelId: _channel!.id,
            onSelect: _selectExisting,
          ),
          const SizedBox(height: AppSpacing.s12),
          AppSegmentedControl.inline(
            semanticLabel: 'Overwrite target kind',
            options: const [
              AppSegmentedOption(label: 'Role'),
              AppSegmentedOption(label: 'Member'),
            ],
            selectedIndex: _kind == api.OverwriteTarget.role ? 0 : 1,
            onSegmentSelected: (i) => setState(() {
              _kind = i == 0
                  ? api.OverwriteTarget.role
                  : api.OverwriteTarget.member;
              _resetTarget();
            }),
          ),
          SettingsSectionCard(
            title: _kind == api.OverwriteTarget.role ? 'Role' : 'Member',
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppListRow(
                label:
                    _targetLabel ??
                    'Choose a ${_kind == api.OverwriteTarget.role ? 'role' : 'member'}',
                trailing: const Icon(
                  AppIcons.chevronRight,
                  size: AppSizes.icon16,
                ),
                onTap: _pickTarget,
              ),
            ],
          ),
        ],
        if (_targetId != null) ...[
          SettingsSectionCard(
            title: 'Permissions',
            description:
                'Each one starts at Inherit because this screen cannot '
                'read back what is already set.',
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (bit, label) in Perm.channelOverwriteEditable)
                PermissionOverwriteRow(
                  label: label,
                  value: _state[bit]!,
                  allowEnabled: myPermissions.hasPermission(bit),
                  onChanged: (v) => setState(() => _state[bit] = v),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Clear',
                  variant: AppButtonVariant.danger,
                  full: true,
                  disabled: _busy,
                  onPressed: _clear,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppButton(
                  label: 'Set overwrite',
                  variant: AppButtonVariant.primary,
                  full: true,
                  disabled: _busy,
                  onPressed: _set,
                ),
              ),
            ],
          ),
          if (actionError != null) ...[
            const SizedBox(height: AppSpacing.s8),
            AppErrorState(message: actionError!, onDismiss: clearActionError),
          ],
        ],
        const SizedBox(height: AppSpacing.s16),
      ],
    );
  }
}
