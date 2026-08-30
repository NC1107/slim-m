// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Voice call preferences: microphone level, camera-on-join, screen share
/// quality, and join/leave sounds.
///
/// Input and output device pickers are deliberately absent. `slimm_rtc`'s
/// public surface ([MediaCapabilities], [VoiceSession]) has no device
/// enumeration or selection: it only counts microphone tracks and screen
/// sources to answer "does this work at all", never which named device
/// answered. Adding one here would mean either reaching past that package
/// into `flutter_webrtc` directly (breaking the one-package rule
/// `voice_session.dart` documents) or inventing a device list nothing
/// backs, so this screen says so instead.
///
/// The state these widgets read and write lives in
/// `providers/voice_settings_controller.dart`, split out once the
/// camera-on-join preference joined the other three.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart' show isDesktopHost;
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';
import '../providers/voice_settings_controller.dart';
import '../widgets/camera_on_join_section.dart';
import '../widgets/media_capability_section.dart';
import '../widgets/settings_section_header.dart';
import '../widgets/settings_toggle_row.dart';

/// Everything about a call this device controls, as a pane body.
///
/// No scaffold of its own: it used to be a screen behind
/// `Routes.voiceSettings`, reached by one row inside personal settings, which
/// is a second route for a category rather than a category. It is the Calls
/// pane of [PersonalSettingsScreen] now, and the route is gone.
class VoiceSettingsBody extends StatelessWidget {
  const VoiceSettingsBody({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      _MicrophoneSection(),
      _SensitivitySection(),
      _PushToTalkSection(),
      CameraOnJoinSection(),
      MediaCapabilitySection(),
      _DeviceSection(),
      _ScreenShareSection(),
      _SoundsSection(),
    ],
  );
}

/// How readily the speaking indicator lights, over and above whatever the
/// SFU itself already decided; see `passesActivationThreshold` in the rtc
/// package for the exact floor. Not wired to the microphone's own capture -
/// checked against the pinned `livekit_client` 2.10.0 source before adding
/// this screen, and it exposes no adjustable noise-gate threshold at all,
/// only on/off capture toggles this client already leaves at their defaults.
class _SensitivitySection extends ConsumerWidget {
  const _SensitivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsControllerProvider);

    return SettingsSectionCard(
      title: 'Voice activity sensitivity',
      description:
          'How much reported volume is needed before the speaking ring '
          'lights up. Lower requires a louder voice; higher lights up on '
          'quieter sound.',
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSlider(
          value: settings.voiceActivitySensitivity,
          ticks: const ['Strict', 'Moderate', 'Loose'],
          semanticLabel: 'Voice activity sensitivity',
          onChanged: (value) => ref
              .read(voiceSettingsControllerProvider.notifier)
              .setVoiceActivitySensitivity(value),
        ),
      ],
    );
  }
}

/// Desktop only: holding a physical key means nothing without one, and this
/// stays out of the tree entirely on a phone rather than offering a control
/// that could never do anything there.
class _PushToTalkSection extends ConsumerWidget {
  const _PushToTalkSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopHost) return const SizedBox.shrink();
    final settings = ref.watch(voiceSettingsControllerProvider);
    final index = pushToTalkKeyOptions.indexOf(settings.pushToTalkKey);

    return SettingsSectionCard(
      title: 'Push-to-talk',
      description:
          'Hold the key below to unmute for as long as you hold it, and '
          'mute again the moment you let go. Held while the message box has '
          'focus types normally instead - it never opens your microphone.',
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsToggleRow(
          label: 'Hold a key to talk, instead of toggling the microphone',
          value: settings.pushToTalkEnabled,
          semanticLabel: 'Push-to-talk',
          onChanged: (value) => ref
              .read(voiceSettingsControllerProvider.notifier)
              .setPushToTalkEnabled(value),
        ),
        if (settings.pushToTalkEnabled) ...[
          const SizedBox(height: AppSpacing.s8),
          AppSegmentedControl.inline(
            semanticLabel: 'Push-to-talk key',
            options: [
              for (final key in pushToTalkKeyOptions)
                AppSegmentedOption(label: _keyLabel(key)),
            ],
            selectedIndex: index < 0 ? 0 : index,
            onSegmentSelected: (i) => ref
                .read(voiceSettingsControllerProvider.notifier)
                .setPushToTalkKey(pushToTalkKeyOptions[i]),
          ),
        ],
      ],
    );
  }

  static String _keyLabel(LogicalKeyboardKey key) => key.keyLabel;
}

/// A live level for the local microphone, sourced from the one real signal
/// `slimm_rtc` exposes: [VoiceParticipant.isSpeaking] on an active call's
/// local participant. There is no continuous amplitude in the package's
/// public API, so this is a two-level meter (quiet or speaking) rather than
/// a fabricated waveform, and it only reads live outside of a call once one
/// starts: there is nothing to meter before that.
class _MicrophoneSection extends ConsumerWidget {
  const _MicrophoneSection();

  static const _quietLevel = 6.0;
  static const _speakingLevel = 82.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    final inCall = voice.state == VoiceSessionState.connected;

    VoiceParticipant? local;
    for (final p in voice.participants) {
      if (p.isLocal) {
        local = p;
        break;
      }
    }
    final speaking = inCall && (local?.isSpeaking ?? false);
    final muted = !inCall || (local?.isMuted ?? true);

    return SettingsSectionCard(
      title: 'Microphone',
      description: 'Your input level while you are in a call.',
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: speaking ? _speakingLevel : _quietLevel),
          duration: AppMotion.reduced(
            context,
            const Duration(milliseconds: 200),
          ),
          builder: (context, level, _) => AppSlider(
            tall: true,
            value: 0,
            onChanged: null,
            meter: level,
            muted: muted,
            semanticLabel: 'Microphone input level',
          ),
        ),
        if (!inCall) ...[
          const SizedBox(height: AppSpacing.s8),
          const AppCallout(
            tone: AppCalloutTone.info,
            child: Text('Join a voice call to see your live input level here.'),
          ),
        ],
      ],
    );
  }
}

/// `slimm_rtc` cannot enumerate audio devices today (confirmed by reading
/// `media_capabilities.dart` and `voice_session.dart`: both only count
/// tracks and sources, neither lists or selects one), so this states that
/// plainly rather than showing a picker with nothing behind it.
class _DeviceSection extends StatelessWidget {
  const _DeviceSection();

  @override
  Widget build(BuildContext context) {
    return const SettingsSectionCard(
      title: 'Input and output devices',
      description: 'Which microphone and speaker a call uses.',
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCallout(
          tone: AppCalloutTone.info,
          icon: AppIcons.headphones,
          child: Text(
            'Device selection is not available in this build yet. Calls '
            "use the operating system's default microphone and speaker.",
          ),
        ),
      ],
    );
  }
}

class _ScreenShareSection extends ConsumerWidget {
  const _ScreenShareSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsControllerProvider);
    final index = ScreenShareQuality.values.indexOf(
      settings.screenShareQuality,
    );
    // A plain getter, not provider state, so `ref.read` rather than `ref.watch`.
    final supportsAudio = ref
        .read(voiceControllerProvider.notifier)
        .supportsScreenShareAudio;

    return SettingsSectionCard(
      title: 'Screen share quality',
      description:
          'A ceiling on resolution and frame rate, not a '
          'preference: it keeps a share from starving the audio '
          'alongside it.',
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSegmentedControl.inline(
          semanticLabel: 'Screen share quality',
          options: [
            for (final quality in ScreenShareQuality.values)
              AppSegmentedOption(label: _label(quality)),
          ],
          selectedIndex: index < 0 ? 1 : index,
          onSegmentSelected: (i) => ref
              .read(voiceSettingsControllerProvider.notifier)
              .setScreenShareQuality(ScreenShareQuality.values[i]),
        ),
        // Absent, never disabled, where this platform cannot publish it; see supportsScreenShareAudio.
        if (supportsAudio) ...[
          const SizedBox(height: AppSpacing.s8),
          SettingsToggleRow(
            label: "Share this device's audio with the screen",
            value: settings.screenShareIncludeAudio,
            semanticLabel: 'Share audio with a screen share',
            onChanged: (value) => ref
                .read(voiceSettingsControllerProvider.notifier)
                .setScreenShareIncludeAudio(value),
          ),
        ],
      ],
    );
  }

  static String _label(ScreenShareQuality q) => switch (q) {
    ScreenShareQuality.smooth => 'Smooth',
    ScreenShareQuality.balanced => 'Balanced',
    ScreenShareQuality.crisp => 'Crisp',
  };
}

class _SoundsSection extends ConsumerWidget {
  const _SoundsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsControllerProvider);

    return SettingsSectionCard(
      title: 'Sounds',
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsToggleRow(
          label: 'Play a sound when someone joins or leaves a call',
          value: settings.joinLeaveSoundsEnabled,
          semanticLabel: 'Play join and leave sounds',
          onChanged: (value) => ref
              .read(voiceSettingsControllerProvider.notifier)
              .setJoinLeaveSoundsEnabled(value),
        ),
        const SizedBox(height: AppSpacing.s8),
        const AppCallout(
          tone: AppCalloutTone.info,
          child: Text(
            'These turn off on their own in a call above about 8 people, '
            'so a busy channel does not turn into a wall of chimes.',
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        SettingsToggleRow(
          label: 'Play a sound for an incoming call',
          value: settings.callRingSoundEnabled,
          semanticLabel: 'Play a sound for an incoming call',
          onChanged: (value) => ref
              .read(voiceSettingsControllerProvider.notifier)
              .setCallRingSoundEnabled(value),
        ),
      ],
    );
  }
}
