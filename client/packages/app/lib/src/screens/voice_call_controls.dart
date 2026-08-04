// SPDX-License-Identifier: Apache-2.0
/// The in-call control bar: mute, camera, screen share and leave.
///
/// Sharing has no quality dialog of its own: the ceiling is whatever Voice
/// settings already has saved (`voice_settings_screen.dart`'s
/// `voiceSettingsControllerProvider`), applied directly rather than asked
/// again on every share, which is what the owner reported as the setting
/// "not mattering".
///
/// The camera button is the same row as hang up, which is where the owner
/// asked for it: no separate toggle lived anywhere in a call before this.
/// Switching cameras once one is on is a bare flip on mobile
/// (`VoiceController.flipCamera`, no device list to show) and a picker on
/// desktop (`camera_source_sheet.dart`), the same fork `screenShareNeedsSource`
/// already draws for sharing.
///
/// Its own file because `voice_screen.dart` was over this repo's hard file
/// limit, and the bar is the one part of that screen with no dependency on
/// which channel is being looked at.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/voice_controller.dart';
import '../widgets/camera_source_sheet.dart';
import '../widgets/screen_source_sheet.dart';
import 'voice_settings_screen.dart' show voiceSettingsControllerProvider;

class CallControls extends ConsumerStatefulWidget {
  const CallControls({
    super.key,
    required this.controller,
    required this.voice,
  });

  final VoiceController controller;
  final VoiceState voice;

  @override
  ConsumerState<CallControls> createState() => _CallControlsState();
}

class _CallControlsState extends ConsumerState<CallControls> {
  /// Guards a fast double-tap from opening two source-selection sheets: the
  /// enumeration and its own sheet run entirely inside [_share], before
  /// [VoiceController.setScreenShare] is ever called, so nothing further down
  /// the stack can catch a re-entrant tap.
  bool _shareRequestInFlight = false;

  /// The same guard as [_shareRequestInFlight], for [_switchCamera].
  bool _cameraSwitchInFlight = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = widget.voice;
    // Decoration outside, SafeArea inside, the same shape the rail's bars use:
    // insetting the bar itself would leave a scaffold-coloured band below it.
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlButton(
                icon: voice.microphoneEnabled ? AppIcons.mic : AppIcons.micOff,
                tooltip: voice.microphoneEnabled ? 'Mute' : 'Unmute',
                active: voice.microphoneEnabled,
                onPressed: widget.controller.toggleMicrophone,
              ),
              const SizedBox(width: AppSpacing.s12),
              _ControlButton(
                icon: voice.cameraEnabled
                    ? AppIcons.camera
                    : AppIcons.cameraOff,
                tooltip: voice.cameraEnabled
                    ? 'Turn off camera'
                    : 'Turn on camera',
                active: voice.cameraEnabled,
                onPressed: () => unawaited(widget.controller.toggleCamera()),
              ),
              if (voice.cameraEnabled) ...[
                const SizedBox(width: AppSpacing.s12),
                _ControlButton(
                  icon: AppIcons.switchCamera,
                  tooltip: 'Switch camera',
                  active: false,
                  pending: _cameraSwitchInFlight,
                  onPressed: () {
                    if (_cameraSwitchInFlight) return;
                    unawaited(_switchCamera(context));
                  },
                ),
              ],
              const SizedBox(width: AppSpacing.s12),
              _ControlButton(
                icon: AppIcons.screenShare,
                tooltip: _shareTooltip(voice),
                active: voice.screenSharing,
                // Pending is its own look, never the active one: the lit
                // button over a share nobody could see was the whole bug.
                pending: voice.awaitingBroadcast,
                onPressed: () {
                  if (_shareRequestInFlight) return;
                  unawaited(_share(context));
                },
              ),
              const SizedBox(width: AppSpacing.s12),
              _ControlButton(
                icon: AppIcons.leaveCall,
                tooltip: 'Leave call',
                active: false,
                destructive: true,
                onPressed: widget.controller.leave,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _shareTooltip(VoiceState voice) {
    if (voice.screenSharing) return 'Stop sharing';
    if (voice.awaitingBroadcast) {
      return 'Waiting for you to start the broadcast. Tap to cancel.';
    }
    return 'Share a screen';
  }

  Future<void> _share(BuildContext context) async {
    final controller = widget.controller;
    final voice = widget.voice;
    // Cancelling a request that never became a broadcast goes down the same
    // path as stopping a live one, which is also what ends the recording.
    if (voice.screenSharing || voice.awaitingBroadcast) {
      await controller.setScreenShare(false);
      return;
    }
    setState(() => _shareRequestInFlight = true);
    try {
      // The saved ceiling, applied directly rather than asked again.
      final quality = ref
          .read(voiceSettingsControllerProvider)
          .screenShareQuality;

      String? sourceId;
      if (controller.screenShareNeedsSource) {
        // Mandatory: capture cannot find a source nothing asked to list.
        final sources = await controller.screenShareSources();
        if (sources.isEmpty) return;
        // On Linux the portal's own picker is the real choice; see DesktopSources.
        if (sources.length == 1 || !controller.screenShareSourcePickerUseful) {
          sourceId = sources.first.id;
        } else {
          if (!context.mounted) return;
          final chosen = await showScreenSourceSheet(context, sources);
          if (chosen == null) return;
          sourceId = chosen.id;
        }
      }
      await controller.setScreenShare(
        true,
        quality: quality,
        sourceId: sourceId,
      );
    } finally {
      if (mounted) setState(() => _shareRequestInFlight = false);
    }
  }

  /// Flips on mobile with no picker at all, and asks on desktop, mirroring
  /// [_share]'s own fork between "the OS decides" and "list, then choose".
  Future<void> _switchCamera(BuildContext context) async {
    final controller = widget.controller;
    setState(() => _cameraSwitchInFlight = true);
    try {
      if (controller.canFlipCamera) {
        await controller.flipCamera();
        return;
      }
      if (!controller.cameraNeedsSelection) return;
      final devices = await controller.cameraDevices();
      if (devices.isEmpty) return;
      if (!context.mounted) return;
      final chosen = await showCameraDeviceSheet(context, devices);
      if (chosen == null) return;
      await controller.selectCameraDevice(chosen);
    } finally {
      if (mounted) setState(() => _cameraSwitchInFlight = false);
    }
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.destructive = false,
    this.pending = false,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final bool destructive;

  /// Asked for, not in effect yet. Reads as busy rather than on.
  ///
  /// On iOS a screen share is a request the user answers in a system picker,
  /// and nothing is published until they do. Drawing that as active describes
  /// a share nobody can see.
  final bool pending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Danger is outlined, never filled: a destructive control must be
    // unmistakable without being the brightest thing on the screen.
    final background = destructive
        ? Colors.transparent
        : active
        ? tokens.accentSoft
        : tokens.surfaceRaised;
    final foreground = destructive
        ? tokens.dangerText
        : active
        ? tokens.accent
        : tokens.textSecondary;
    final border = destructive ? tokens.dangerBorder : tokens.borderSubtle;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: Container(
            // 44 is the touch minimum; it does not shrink on desktop, because
            // one control size across widths is what "one layout" has to mean.
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: border),
            ),
            child: pending
                ? Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.textSecondary,
                      ),
                    ),
                  )
                : Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}
