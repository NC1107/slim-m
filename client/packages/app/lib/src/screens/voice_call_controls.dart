// SPDX-License-Identifier: Apache-2.0
/// The in-call controls: mute, camera, screen share and leave.
///
/// Sharing has no quality dialog of its own: the ceiling, and whether to
/// include this device's own audio, are whatever Voice settings already has
/// saved (`voice_settings_screen.dart`'s `voiceSettingsControllerProvider`),
/// applied directly rather than asked again on every share, which is what
/// the owner reported as the quality setting "not mattering".
///
/// The camera button is the same row as hang up, which is where the owner
/// asked for it: no separate toggle lived anywhere in a call before this.
/// Switching cameras once one is on is a bare flip on mobile
/// (`VoiceController.flipCamera`, no device list to show) and a picker on
/// desktop (`camera_source_sheet.dart`), the same fork `screenShareNeedsSource`
/// already draws for sharing. The switch button itself only shows on a
/// picker platform once `cameraDevices()` has resolved to more than one
/// deduplicated entry, so a desktop with one physical webcam that happens to
/// enumerate several V4L2 nodes never offers a choice there is none of.
///
/// This widget is a bare row now, not a bar: it used to paint its own
/// full-width, edge-anchored strip, which is exactly what made opening the
/// canvas make it disappear outright (`ConversationPane` swaps the whole
/// pane, controls included) rather than merely getting out of the way. The
/// shell - a floating card, positioned and sized by whoever is showing this
/// call right now - lives in `FloatingDockCard` and `canvas_call_dock.dart`
/// instead, so a call's controls can sit inside the identical card a
/// canvas's controls do, combined, whenever both are relevant at once.
///
/// Its own file because `voice_screen.dart` was over this repo's hard file
/// limit, and this row is the one part of that screen with no dependency on
/// which channel is being looked at.
///
/// **`CallDockButton` used to draw a fixed 44dp chip at every width**, the
/// single largest contributor to the owner's "way more compact" report.
/// It now follows `AppIconButton`'s own already-tested split instead
/// (`design_system/test/touch_targets_test.dart`): a fixed visible chip,
/// with only the invisible tap area growing to `AppSizes.rowTouch` at
/// touch density. Public now, since `voice_call_dock.dart`'s canvas toggle
/// draws the identical chip.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart' show apiProvider;
import '../providers/voice_controller.dart';
import '../providers/voice_flags.dart';
import '../providers/voice_settings_controller.dart'
    show voiceSettingsControllerProvider;
import '../widgets/camera_source_sheet.dart';
import '../widgets/screen_source_sheet.dart';

class CallControls extends ConsumerStatefulWidget {
  const CallControls({
    super.key,
    required this.controller,
    required this.voice,
  });

  final VoiceController controller;

  /// Only the flags half of the call: this row never has any use for the
  /// roster, and typing it this way keeps a future caller from threading it
  /// back in the way `railVoiceToggleButtons` used to.
  final VoiceFlags voice;

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

  /// The deduplicated camera count a picker platform found on mount, once
  /// [_loadCameraCount] resolves; unused on a platform that flips instead
  /// (see [_canSwitchCamera]). Null until then, which reads as "cannot
  /// switch" rather than flashing the button on and immediately off: a
  /// picker platform is exactly the one where duplicate device nodes
  /// (`camera_devices.dart`'s `dedupeCameraDevices`) made an unresolved
  /// count worse than a briefly-late one.
  int? _desktopCameraCount;

  @override
  void initState() {
    super.initState();
    if (!widget.controller.canFlipCamera) unawaited(_loadCameraCount());
  }

  Future<void> _loadCameraCount() async {
    final devices = await widget.controller.cameraDevices();
    if (!mounted) return;
    setState(() => _desktopCameraCount = devices.length);
  }

  /// Whether there is actually another camera to switch to: a bare flip
  /// needs no device list, since mobile's own OS decides "front" or "back";
  /// a picker platform needs its enumerated, deduplicated count above one,
  /// or the button offers a choice that does not exist.
  bool get _canSwitchCamera =>
      widget.controller.canFlipCamera || (_desktopCameraCount ?? 0) > 1;

  @override
  Widget build(BuildContext context) {
    final voice = widget.voice;
    // mainAxisSize.min: this row sizes to its own content now that it has no
    // full-width bar to fill, so whatever floating card embeds it - alone or
    // beside a canvas's own controls - can size itself to match.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CallDockButton(
          icon: voice.microphoneEnabled ? AppIcons.mic : AppIcons.micOff,
          tooltip: voice.microphoneEnabled ? 'Mute' : 'Unmute',
          active: voice.microphoneEnabled,
          onPressed: widget.controller.toggleMicrophone,
        ),
        const SizedBox(width: AppSpacing.s8),
        CallDockButton(
          icon: voice.cameraEnabled ? AppIcons.camera : AppIcons.cameraOff,
          tooltip: voice.cameraEnabled ? 'Turn off camera' : 'Turn on camera',
          active: voice.cameraEnabled,
          onPressed: () => unawaited(widget.controller.toggleCamera()),
        ),
        if (voice.cameraEnabled && _canSwitchCamera) ...[
          const SizedBox(width: AppSpacing.s8),
          CallDockButton(
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
        const SizedBox(width: AppSpacing.s8),
        CallDockButton(
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
        const SizedBox(width: AppSpacing.s8),
        CallDockButton(
          icon: AppIcons.leaveCall,
          tooltip: 'Leave call',
          active: false,
          destructive: true,
          onPressed: widget.controller.leave,
        ),
      ],
    );
  }

  static String _shareTooltip(VoiceFlags voice) {
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
      // The saved ceiling and audio choice, applied directly rather than asked again.
      final settings = ref.read(voiceSettingsControllerProvider);
      final quality = settings.screenShareQuality;

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
        includeAudio: settings.screenShareIncludeAudio,
        maxHeight: await _screenShareCeiling(),
      );
    } finally {
      if (mounted) setState(() => _shareRequestInFlight = false);
    }
  }

  /// The space-wide screen-share ceiling, or `null` on any failure to fetch
  /// it, or on a server too old to report one. Read from `GET /version`,
  /// unauthenticated, rather than the MANAGE_SERVER-gated
  /// `GET /space/screen-share` the admin screen uses: every device sharing a
  /// screen has to know this, not only one with an admin bit. This is a
  /// client-advertised courtesy cap, not a security boundary, so a Space
  /// this device cannot reach right now must not be the reason a share never
  /// starts: failing open publishes at the quality already chosen, exactly
  /// what happened before this setting existed.
  Future<int?> _screenShareCeiling() async {
    try {
      final version = await ref.read(apiProvider).version();
      return version.screenShareMaxHeight;
    } catch (_) {
      return null;
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
      // A single-entry list has nothing to choose between, mirroring _share.
      if (devices.length == 1) {
        await controller.selectCameraDevice(devices.first);
        return;
      }
      final chosen = await showCameraDeviceSheet(context, devices);
      if (chosen == null) return;
      await controller.selectCameraDevice(chosen);
    } finally {
      if (mounted) setState(() => _cameraSwitchInFlight = false);
    }
  }
}

class CallDockButton extends StatelessWidget {
  const CallDockButton({
    super.key,
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

    // AppIconButton's own split: a fixed visible chip, with the invisible
    // tap area alone growing to AppSizes.rowTouch at touch density.
    final touch = AppTouchTargets.of(context);
    final hitTarget = touch ? AppSizes.rowTouch : AppSizes.rowPointer;
    const visualSize = AppSizes.controlMd;
    final outerSize = visualSize > hitTarget ? visualSize : hitTarget;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: AppFocusRing(
          radius: AppRadii.control,
          builder: (context, onFocusChange) => InkWell(
            onTap: onPressed,
            // AppFocusRing replaces this overlay; see its own doc comment.
            focusColor: Colors.transparent,
            onFocusChange: onFocusChange,
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: SizedBox(
              width: outerSize,
              height: outerSize,
              child: Center(
                child: Container(
                  width: visualSize,
                  height: visualSize,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    border: Border.all(color: border),
                  ),
                  child: pending
                      ? Center(
                          child: SizedBox(
                            width: AppSizes.icon16,
                            height: AppSizes.icon16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.textSecondary,
                            ),
                          ),
                        )
                      : Icon(icon, size: AppSizes.icon16, color: foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
