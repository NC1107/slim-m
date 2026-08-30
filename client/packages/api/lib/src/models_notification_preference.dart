// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The caller's own push notification preference: which messages are worth
/// waking a device for.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// What a message has to be before it wakes one of this account's devices.
///
/// Enforced server-side, in `push::recipients::message_recipients` - never a
/// client-side filter, so choosing [mentions] or [nothing] means a device
/// genuinely does not buzz, rather than buzzing and being silenced here
/// after the fact.
enum NotificationPreference {
  /// Every message in a channel this account can see. The default, and what
  /// every account already got before this preference existed.
  everything,

  /// A direct `@`-mention, plus every message in a DM: somebody messaging
  /// this account in a DM is addressing them directly, the same as a
  /// mention.
  mentions,

  /// No push at all, ever, including a DM.
  nothing;

  String get wire => name;

  /// An unrecognised value reads as [everything], matching the server's own
  /// fallback for a stored value it cannot parse (`NotificationPreference`'s
  /// own doc comment in `crates/slimm-server/src/notifications.rs`): there is
  /// no live safety consequence to misreading this one way or the other, so
  /// client and server agree on the same default rather than each guessing
  /// differently.
  static NotificationPreference parse(String value) => switch (value) {
        'mentions' => NotificationPreference.mentions,
        'nothing' => NotificationPreference.nothing,
        _ => NotificationPreference.everything,
      };
}
