// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The presses this client has sent to a bot and not yet seen answered.
///
/// A press is pending until the bot answers it (`interaction.answered`) and
/// fails visibly if the request is refused or nothing comes back in time. It
/// is in memory only: the server keeps a press for a quarter of an hour and
/// nothing here should outlive a reload. See
/// docs/decisions/0038-bot-message-buttons.md.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../api_failure.dart';
import '../ids.dart';
import 'live_events.dart';
import 'providers.dart';

/// How long a press waits for the bot before it is shown as failed.
const Duration buttonPressTimeout = Duration(seconds: 5);

enum ButtonPressStatus { pending, failed }

class ButtonPress {
  const ButtonPress({
    required this.id,
    required this.channelId,
    required this.messageId,
    required this.customId,
    required this.status,
    this.failure,
  });

  final String id;
  final String channelId;
  final String messageId;
  final String customId;
  final ButtonPressStatus status;

  /// Plain words for the person, set only when [status] is failed.
  final String? failure;

  bool get pending => status == ButtonPressStatus.pending;
}

String _keyOf(String messageId, String customId) => '$messageId|$customId';

class ButtonPressesController extends StateNotifier<Map<String, ButtonPress>> {
  ButtonPressesController(this._ref, {Duration timeout = buttonPressTimeout})
    : _timeout = timeout,
      super(const {}) {
    _sub = _ref.read(liveEventsProvider).listen((event) {
      if (event case api.InteractionAnswered(:final interactionId)) {
        _answered(interactionId);
      }
    });
  }

  final Ref _ref;
  final Duration _timeout;
  late final StreamSubscription<api.ServerEvent> _sub;
  final Map<String, Timer> _timers = {};

  /// Ignored while the same button on the same message is already pending.
  Future<void> press({
    required String channelId,
    required String messageId,
    required String customId,
  }) async {
    final key = _keyOf(messageId, customId);
    if (state[key]?.pending ?? false) return;
    final id = newMessageId();
    _put(
      key,
      ButtonPress(
        id: id,
        channelId: channelId,
        messageId: messageId,
        customId: customId,
        status: ButtonPressStatus.pending,
      ),
    );
    _timers[key]?.cancel();
    _timers[key] = Timer(_timeout, () {
      _fail(
        key,
        id,
        'The bot did not answer. It may be offline, so try again in a moment.',
      );
    });
    try {
      await _ref
          .read(apiProvider)
          .pressMessageButton(
            channelId: channelId,
            messageId: messageId,
            id: id,
            customId: customId,
          );
    } on api.ApiException catch (e) {
      _fail(key, id, _describe(e));
    }
  }

  String _describe(api.ApiException e) => switch (e) {
    api.NotFoundException() =>
      'That button is no longer available. The bot or its message may be gone.',
    _ => describeApiFailure('press that button', e),
  };

  void _answered(String interactionId) {
    for (final entry in state.entries) {
      if (entry.value.id != interactionId) continue;
      _timers.remove(entry.key)?.cancel();
      _remove(entry.key);
      return;
    }
  }

  void _fail(String key, String id, String failure) {
    final current = state[key];
    if (current == null || current.id != id || !current.pending) return;
    _timers.remove(key)?.cancel();
    _put(
      key,
      ButtonPress(
        id: id,
        channelId: current.channelId,
        messageId: current.messageId,
        customId: current.customId,
        status: ButtonPressStatus.failed,
        failure: failure,
      ),
    );
  }

  /// Clears a failure the person has read or wants to retry past.
  void dismiss(String messageId, String customId) {
    final key = _keyOf(messageId, customId);
    if (state[key]?.pending ?? true) return;
    _remove(key);
  }

  void _put(String key, ButtonPress press) => state = {...state, key: press};

  void _remove(String key) {
    state = {
      for (final entry in state.entries)
        if (entry.key != key) entry.key: entry.value,
    };
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}

/// Not `autoDispose`: a press must keep waiting while its channel is off
/// screen for a moment.
final buttonPressesProvider =
    StateNotifierProvider<ButtonPressesController, Map<String, ButtonPress>>(
      (ref) => ButtonPressesController(ref),
    );

/// The press state of one message's buttons, by `custom_id`.
final messageButtonPressesProvider =
    Provider.family<Map<String, ButtonPress>, String>((ref, messageId) {
      final all = ref.watch(buttonPressesProvider);
      return {
        for (final press in all.values)
          if (press.messageId == messageId) press.customId: press,
      };
    });
