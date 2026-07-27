// SPDX-License-Identifier: Apache-2.0
/// A client-side mirror of `crates/slimm-server/src/permissions.rs`.
///
/// Every bit here must match the server's `Permissions` constants exactly:
/// this is what `Me.permissions` and `Role.permissions` are bitmasks of. Used
/// only to decide what to show; every write is still re-authorized
/// server-side from scratch regardless of what a caller can see.
library;

abstract final class Perm {
  static const int administrator = 1 << 0;
  static const int viewChannel = 1 << 1;
  static const int sendMessages = 1 << 2;
  static const int manageMessages = 1 << 3;
  static const int manageChannels = 1 << 4;
  static const int manageRoles = 1 << 5;
  static const int kickMembers = 1 << 6;
  static const int banMembers = 1 << 7;
  static const int createInvite = 1 << 8;
  static const int addReactions = 1 << 9;
  static const int attachFiles = 1 << 10;
  static const int connect = 1 << 11;
  static const int speak = 1 << 12;
  static const int useCanvas = 1 << 13;
  static const int manageCanvas = 1 << 14;
  static const int manageServer = 1 << 15;

  /// Every bit that has a name, in the fixed order the editor lists them.
  static const List<(int bit, String label)> editable = [
    (administrator, 'Administrator'),
    (viewChannel, 'View channels'),
    (sendMessages, 'Send messages'),
    (manageMessages, 'Manage messages'),
    (manageChannels, 'Manage channels'),
    (manageRoles, 'Manage roles'),
    (kickMembers, 'Kick members'),
    (banMembers, 'Ban members'),
    (createInvite, 'Create invites'),
    (addReactions, 'Add reactions'),
    (attachFiles, 'Attach files'),
    (connect, 'Join voice channels'),
    (speak, 'Speak in voice channels'),
    (useCanvas, 'Use the voice canvas'),
    (manageCanvas, 'Manage the voice canvas'),
    (manageServer, 'Manage community settings'),
  ];
}

/// Whether a raw permission bitmask contains every bit in [required].
/// Mirrors the server's own `contains`: [administrator] is not special-cased
/// here, matching `Me.permissions` and `Role.permissions`, which already
/// carry it as an ordinary bit a caller can check for directly.
extension PermissionCheck on int {
  bool hasPermission(int required) => (this & required) == required;
}
