// SPDX-License-Identifier: Apache-2.0
part of 'voice_controller.dart';

/// Push-to-talk and voice-activity sensitivity, split out for
/// [VoiceController]'s own 500-line hard ceiling. A mixin rather than an
/// extension: once mixed in it is a real member of the class hierarchy, so
/// [state] (`StateNotifier`'s own accessor, `@protected`/`@visibleForTesting`)
/// is reachable the way it would be from any other method declared on
/// [VoiceController] itself - an extension is never that, however private
/// its name or however it reaches this file.
mixin VoiceControllerInputMixin on StateNotifier<VoiceState> {
  /// Bridges to [VoiceController]'s own private fields; declared abstract
  /// here because a mixin's `on` clause, not shared-library privacy, is what
  /// bounds which members it can reach through an implicit receiver.
  VoiceSession get _inputSession;
  Ref get _inputRef;

  /// [VoiceController.restoreCameraPreference]'s own shape, for the
  /// session's speaking threshold: it already exists at construction, so
  /// this only has to run once, before any call.
  Future<void> restoreVoiceActivitySensitivity() async {
    _inputSession.setSpeakingSensitivity(
      await loadVoiceActivitySensitivity(_inputRef) / 100,
    );
  }

  /// Live, in-call equivalent of [restoreVoiceActivitySensitivity].
  void setVoiceActivitySensitivity(double sensitivityPercent) {
    _inputSession.setSpeakingSensitivity(sensitivityPercent / 100);
  }

  /// Push-to-talk's own entry point: sets the microphone explicitly to
  /// [heldOpen] rather than flipping it, since a repeated or out-of-order
  /// key event must never invert this. A no-op outside a live call, so a
  /// key held before joining or after leaving cannot corrupt
  /// [VoiceState.microphoneEnabled]'s other duty as the pre-join preference.
  Future<void> setPushToTalkHeld(bool heldOpen) async {
    if (state.state != VoiceSessionState.connected) return;
    final got = await _inputSession.setMicrophoneEnabled(heldOpen);
    state = state.copyWith(
      microphoneEnabled: got ? heldOpen : state.microphoneEnabled,
    );
  }
}
