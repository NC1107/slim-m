// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The account's linked devices: the list, each device's own sign-out, and
/// signing every other device out in one action.
///
/// Split out of `personal_account_sections.dart`, which had no line budget
/// left for the bulk sign-out this file adds.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import 'confirm_dialog.dart';
import 'run_guarded.dart';
import 'settings_section_header.dart';

/// The account's devices, refetched when invalidated.
final devicesProvider = FutureProvider.autoDispose<List<api.Device>>(
  (ref) => ref.watch(apiProvider).listDevices(),
);

class DevicesSection extends ConsumerStatefulWidget {
  const DevicesSection({super.key});

  @override
  ConsumerState<DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends ConsumerState<DevicesSection> {
  bool _signingOutAll = false;

  /// Names of the devices a bulk sign-out could not reach, or null once
  /// cleared. Kept as names rather than a count: "someone is in my account,
  /// kick everyone else out" deserves to know exactly what is still signed
  /// in, not just that something is.
  String? _bulkError;

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return SettingsSectionCard(
      title: 'Devices',
      description: 'Everywhere this account is signed in.',
      children: [
        devices.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.s8),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => const Padding(
            padding: EdgeInsets.all(AppSpacing.s8),
            child: Text('Could not load devices.'),
          ),
          // Named like Blocked's empty state below: an empty card reads as a loading glitch, not an intentional state.
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.s8),
                  child: Text(
                    'No devices signed in.',
                    style: AppText.body.copyWith(color: tokens.textSecondary),
                  ),
                )
              : _buildDeviceList(context, tokens, list),
        ),
      ],
    );
  }

  Widget _buildDeviceList(
    BuildContext context,
    AppTokens tokens,
    List<api.Device> list,
  ) {
    final others = list.where((d) => !d.isCurrent).toList();
    return Column(
      children: [
        for (final device in list)
          _DeviceRow(key: ValueKey(device.id), device: device),
        if (others.isNotEmpty) ...[
          AppListRow(
            leading: Icon(
              AppIcons.signOut,
              size: AppSizes.icon16,
              color: tokens.dangerText,
            ),
            label: 'Sign out all other devices',
            onTap: _signingOutAll
                ? null
                : () => _confirmSignOutAllOthers(context, others),
          ),
          if (_bulkError case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                0,
                AppSpacing.s16,
                AppSpacing.s8,
              ),
              child: AppErrorState(
                message: error,
                onDismiss: () => setState(() => _bulkError = null),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _confirmSignOutAllOthers(
    BuildContext context,
    List<api.Device> others,
  ) async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Sign out all other devices?',
      message:
          'Every device but this one is logged out right away and has to '
          'sign in again to use this account.',
      confirmLabel: 'Sign out all',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _signingOutAll = true;
      _bulkError = null;
    });
    final remaining = <String>[];
    for (final device in others) {
      try {
        await ref.read(apiProvider).removeDevice(device.id);
      } on api.ApiException {
        remaining.add(device.name);
      }
    }
    ref.invalidate(devicesProvider);
    if (!mounted) return;
    setState(() {
      _signingOutAll = false;
      _bulkError = remaining.isEmpty
          ? null
          : 'Could not sign out ${remaining.join(', ')}. Still signed in.';
    });
  }
}

/// The kind of thing a device is, guessed from the name it registered with
/// ("iOS (localhost)", "Linux (fedora)", "desktop").
///
/// A guess, deliberately: the name is a free string the client picks at
/// sign-in, and the server stores no platform of its own. Getting it wrong
/// costs a slightly wrong glyph, and getting it right is what makes a list of
/// sessions scannable for the one you do not recognise.
IconData deviceIcon(String name) {
  final lower = name.toLowerCase();
  const phones = ['ios', 'iphone', 'ipad', 'android', 'phone', 'mobile'];
  const laptops = ['macbook', 'laptop', 'linux', 'fedora', 'ubuntu', 'debian'];
  if (phones.any(lower.contains)) return AppIcons.devicePhone;
  if (laptops.any(lower.contains)) return AppIcons.deviceLaptop;
  return AppIcons.deviceDesktop;
}

/// When a device was last seen, as a phrase rather than "Signed in" - which
/// every row said, about every device, and so told a reader nothing.
String lastUsed(int? lastSeenAt) {
  if (lastSeenAt == null) return 'Signed in';
  final delta = DateTime.now().millisecondsSinceEpoch - lastSeenAt;
  if (delta < 60 * 1000) return 'Active now';
  if (delta < 60 * 60 * 1000) return 'Last used ${delta ~/ (60 * 1000)}m ago';
  if (delta < 24 * 60 * 60 * 1000) {
    return 'Last used ${delta ~/ (60 * 60 * 1000)}h ago';
  }
  return 'Last used ${delta ~/ (24 * 60 * 60 * 1000)}d ago';
}

/// One signed-in device, with its own "sign out" failure: a revoke that
/// cannot reach the server must say so on the row it was for, not vanish.
///
/// The sign-out is a dismiss glyph that shows on hover (always, on touch,
/// where there is no hover), behind a confirmation that says what it does.
/// A labelled button on every row made the list read as four calls to
/// action; the owner asked for "an on hover X with a popup saying it will
/// log them out". Signing a device out is rare and consequential enough
/// that the pause the popup adds is the right cost.
class _DeviceRow extends ConsumerStatefulWidget {
  const _DeviceRow({super.key, required this.device});

  final api.Device device;

  @override
  ConsumerState<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends ConsumerState<_DeviceRow>
    with GuardedActionState<_DeviceRow> {
  bool _busy = false;
  bool _hovered = false;
  bool _focused = false;

  Future<void> _confirmSignOut() async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Sign out ${widget.device.name}?',
      message:
          'That device is logged out right away and has to sign in again '
          'to use this account.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed || !mounted) return;
    await _signOut();
  }

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
    final device = widget.device;
    final shown = AppTouchTargets.of(context) || _hovered || _focused || _busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AppListRow(
            leading: Icon(deviceIcon(device.name)),
            label: device.name,
            meta: device.isCurrent
                ? 'This device'
                : lastUsed(device.lastSeenAt),
            trailing: device.isCurrent
                ? null
                : Focus(
                    onFocusChange: (v) => setState(() => _focused = v),
                    child: AnimatedOpacity(
                      opacity: shown ? 1 : 0,
                      duration: AppMotion.reduced(context, AppMotion.fast),
                      // Hidden from the eye is not hidden from a screen reader.
                      alwaysIncludeSemantics: true,
                      child: AppIconButton(
                        icon: AppIcons.dismiss,
                        semanticLabel: 'Sign out ${device.name}',
                        tooltip: 'Sign out this device',
                        size: AppIconButtonSize.sm,
                        onPressed: _busy ? null : _confirmSignOut,
                      ),
                    ),
                  ),
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
