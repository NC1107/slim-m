// SPDX-License-Identifier: Apache-2.0
/// Per-channel permission overwrites: `PUT`/`DELETE
/// /channels/{channelId}/overwrites/{kind}/{id}`. Requires MANAGE_ROLES in
/// the target channel.
///
/// There is no endpoint to read an existing overwrite back, only to set
/// (replace) or clear one, so this screen never claims to show current
/// state: every permission opens on "inherit" and a submit always replaces
/// whatever was there, sight unseen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart' show Channel;
import 'package:slimm_design_system/design_system.dart';

import '../../permissions.dart';
import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../../widgets/confirm_dialog.dart';
import 'overwrite_target_picker_sheets.dart';
import 'permission_overwrite_row.dart';

class ChannelOverwritesScreen extends ConsumerStatefulWidget {
  const ChannelOverwritesScreen({super.key});

  @override
  ConsumerState<ChannelOverwritesScreen> createState() =>
      _ChannelOverwritesScreenState();
}

class _ChannelOverwritesScreenState
    extends ConsumerState<ChannelOverwritesScreen> {
  Channel? _channel;
  api.OverwriteTarget _kind = api.OverwriteTarget.role;
  String? _targetId;
  String? _targetLabel;
  final Map<int, OverwriteState> _state = {
    for (final p in Perm.editable) p.$1: OverwriteState.inherit,
  };
  bool _busy = false;

  void _resetTarget() {
    _targetId = null;
    _targetLabel = null;
    _resetState();
  }

  void _resetState() => _state.updateAll((_, __) => OverwriteState.inherit);

  Future<void> _pickChannel() async {
    final store = await ref.read(storeProvider.future);
    final channels = await store.watchChannels().first;
    if (!mounted) return;
    final picked = await showModalBottomSheet<Channel>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final c in channels)
            ListTile(
              leading: Icon(c.kind == 'voice' ? AppIcons.voice : AppIcons.hash),
              title: Text(c.name),
              onTap: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _channel = picked;
      _resetTarget();
    });
  }

  Future<void> _pickTarget() async {
    if (_kind == api.OverwriteTarget.role) {
      final picked = await showModalBottomSheet<api.Role>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => const RolePickerSheet(),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _targetId = picked.id;
        _targetLabel = picked.name;
        _resetState();
      });
    } else {
      final picked = await showModalBottomSheet<api.UserProfile>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => const MemberPickerSheet(),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _targetId = picked.id;
        _targetLabel = picked.displayName;
        _resetState();
      });
    }
  }

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
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).setChannelOverwrite(
            channelId: _channel!.id,
            kind: _kind,
            id: _targetId!,
            allow: allow,
            deny: deny,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Overwrite set for $_targetLabel.')),
      );
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not set the overwrite. ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Clear this overwrite?',
      message: 'Every permission for $_targetLabel in "${_channel!.name}" '
          'goes back to inheriting from their roles. This cannot be undone.',
      confirmLabel: 'Clear',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).deleteChannelOverwrite(
            channelId: _channel!.id,
            kind: _kind,
            id: _targetId!,
          );
      if (!mounted) return;
      setState(_resetState);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Overwrite cleared for $_targetLabel.')),
      );
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear the overwrite. ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A floor, not the exact figure: the server checks "allow" against the
    // caller's effective permissions in this specific channel, which a
    // per-channel overwrite of the caller's own can raise above their base
    // set. There is no endpoint to read that per-channel figure, so this
    // uses the base (deployment-level) set from `/me` as a safe, possibly
    // stricter, stand-in.
    final myPermissions = ref.watch(myPermissionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel permissions'),
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          tooltip: 'Back to settings',
          onPressed: () => context.go(Routes.settings),
        ),
      ),
      // top: false because the AppBar already clears the status bar.
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          children: [
            const AppCallout(
              tone: AppCalloutTone.info,
              child: Text(
                'There is no way to read an existing overwrite back, so this '
                'always starts from "inherit". Setting one replaces whatever '
                'was there for every permission at once.',
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            AppCard(
              title: 'Channel',
              // The card's own background sits between a bare ListTile and the
              // Scaffold's Material, which swallows its ink splash; a
              // transparent Material here gives the splash somewhere to paint.
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_channel?.name ?? 'Choose a channel'),
                  trailing: const Icon(AppIcons.chevronRight),
                  onTap: _pickChannel,
                ),
              ),
            ),
            if (_channel != null) ...[
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
              const SizedBox(height: AppSpacing.s12),
              AppCard(
                title: _kind == api.OverwriteTarget.role ? 'Role' : 'Member',
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_targetLabel ??
                        'Choose a ${_kind == api.OverwriteTarget.role ? 'role' : 'member'}'),
                    trailing: const Icon(AppIcons.chevronRight),
                    onTap: _pickTarget,
                  ),
                ),
              ),
            ],
            if (_targetId != null) ...[
              const SizedBox(height: AppSpacing.s16),
              for (final (bit, label) in Perm.editable)
                PermissionOverwriteRow(
                  label: label,
                  value: _state[bit]!,
                  allowEnabled: myPermissions.hasPermission(bit),
                  onChanged: (v) => setState(() => _state[bit] = v),
                ),
              const SizedBox(height: AppSpacing.s8),
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
            ],
            const SizedBox(height: AppSpacing.s16),
          ],
        ),
      ),
    );
  }
}
