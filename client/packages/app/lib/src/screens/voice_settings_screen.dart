// SPDX-License-Identifier: Apache-2.0
/// Voice call preferences: microphone level, screen share quality, and
/// join/leave sounds.
///
/// Input and output device pickers are deliberately absent. `slimm_rtc`'s
/// public surface ([MediaCapabilities], [VoiceSession]) has no device
/// enumeration or selection: it only counts microphone tracks and screen
/// sources to answer "does this work at all", never which named device
/// answered. Adding one here would mean either reaching past that package
/// into `flutter_webrtc` directly (breaking the one-package rule
/// `voice_session.dart` documents) or inventing a device list nothing
/// backs, so this screen says so instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/providers.dart';
import '../providers/voice_controller.dart';
import '../routing/routes.dart';
import '../widgets/media_capability_section.dart';

const _soundsKey = 'slimm.voice.join_leave_sounds_enabled';
const _qualityKey = 'slimm.voice.screen_share_quality';

/// What this screen shows and edits. Both fields are pure local device
/// preferences with no server truth, unlike [presenceVisibilityDisplayProvider]'s
/// session-only echo, so they are persisted in [preferencesProvider] and
/// read back on the next launch.
class VoiceSettingsState {
  const VoiceSettingsState({
    this.joinLeaveSoundsEnabled = true,
    this.screenShareQuality = ScreenShareQuality.balanced,
  });

  final bool joinLeaveSoundsEnabled;
  final ScreenShareQuality screenShareQuality;

  VoiceSettingsState copyWith({
    bool? joinLeaveSoundsEnabled,
    ScreenShareQuality? screenShareQuality,
  }) => VoiceSettingsState(
    joinLeaveSoundsEnabled:
        joinLeaveSoundsEnabled ?? this.joinLeaveSoundsEnabled,
    screenShareQuality: screenShareQuality ?? this.screenShareQuality,
  );
}

class VoiceSettingsController extends StateNotifier<VoiceSettingsState> {
  VoiceSettingsController(this._ref) : super(const VoiceSettingsState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final prefs = await _ref.read(preferencesProvider.future);
    final storedQuality = prefs.getString(_qualityKey);
    state = state.copyWith(
      joinLeaveSoundsEnabled: prefs.getBool(_soundsKey) ?? true,
      screenShareQuality: ScreenShareQuality.values
          .where((q) => q.name == storedQuality)
          .firstOrDefault(ScreenShareQuality.balanced),
    );
  }

  Future<void> setJoinLeaveSoundsEnabled(bool enabled) async {
    state = state.copyWith(joinLeaveSoundsEnabled: enabled);
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setBool(_soundsKey, enabled);
  }

  Future<void> setScreenShareQuality(ScreenShareQuality quality) async {
    state = state.copyWith(screenShareQuality: quality);
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setString(_qualityKey, quality.name);
  }
}

extension _FirstOrDefault<T> on Iterable<T> {
  T firstOrDefault(T fallback) => isEmpty ? fallback : first;
}

final voiceSettingsControllerProvider =
    StateNotifierProvider<VoiceSettingsController, VoiceSettingsState>(
      (ref) => VoiceSettingsController(ref),
    );

class VoiceSettingsScreen extends ConsumerWidget {
  const VoiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice settings'),
        // Same reasoning as SettingsScreen's back button: this route can be
        // reached directly, so there is not always a stack to pop.
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          tooltip: 'Back to settings',
          onPressed: () => context.go(Routes.settings),
        ),
      ),
      // top: false because the AppBar already clears the status bar; without
      // the bottom edge the last section runs under the home indicator.
      body: SafeArea(
        top: false,
        child: ListView(
          children: const [
            _MicrophoneSection(),
            Divider(height: 1),
            MediaCapabilitySection(),
            Divider(height: 1),
            _DeviceSection(),
            Divider(height: 1),
            _ScreenShareSection(),
            Divider(height: 1),
            _SoundsSection(),
          ],
        ),
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
            style: AppText.ui.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              description!,
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          'Microphone',
          description: 'Your input level while you are in a call.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: speaking ? _speakingLevel : _quietLevel),
            duration: const Duration(milliseconds: 200),
            builder: (context, level, _) => AppSlider(
              tall: true,
              value: 0,
              onChanged: null,
              meter: level,
              muted: muted,
              semanticLabel: 'Microphone input level',
            ),
          ),
        ),
        if (!inCall) ...[
          const SizedBox(height: AppSpacing.s8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            child: AppCallout(
              tone: AppCalloutTone.info,
              child: Text(
                'Join a voice call to see your live input level here.',
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s16),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          'Input and output devices',
          description: "Which microphone and speaker a call uses.",
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            0,
            AppSpacing.s16,
            AppSpacing.s16,
          ),
          child: AppCallout(
            tone: AppCalloutTone.info,
            icon: AppIcons.headphones,
            child: Text(
              'Device selection is not available in this build yet. Calls '
              "use the operating system's default microphone and speaker.",
            ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          'Screen share quality',
          description:
              'A ceiling on resolution and frame rate, not a '
              'preference: it keeps a share from starving the audio '
              'alongside it.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          child: AppSegmentedControl.inline(
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
        ),
        const SizedBox(height: AppSpacing.s16),
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
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final settings = ref.watch(voiceSettingsControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Sounds'),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Play a sound when someone joins or leaves a call',
                  style: TextStyle(color: tokens.textPrimary),
                ),
              ),
              AppToggle(
                value: settings.joinLeaveSoundsEnabled,
                onChanged: (value) => ref
                    .read(voiceSettingsControllerProvider.notifier)
                    .setJoinLeaveSoundsEnabled(value),
                semanticLabel: 'Play join and leave sounds',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          child: AppCallout(
            tone: AppCalloutTone.info,
            child: Text(
              'These turn off on their own in a call above about 8 people, '
              'so a busy channel does not turn into a wall of chimes.',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
      ],
    );
  }
}
