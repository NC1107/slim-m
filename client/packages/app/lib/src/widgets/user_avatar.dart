// SPDX-License-Identifier: Apache-2.0
/// [AppAvatar], wired to a real picture: watches the user's cached avatar
/// bytes and swaps them in once they arrive, falling back to the same
/// initials disc `AppAvatar` already draws for everyone without one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/avatar_bytes.dart';
import '../providers/user_profiles.dart';

/// For a caller that already holds a full profile (or `Me`) and so knows
/// [userId] and [avatarUpdatedAt] outright: a member row, the caller's own
/// rail footer, the settings preview.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.userId,
    this.avatarUpdatedAt,
    this.size = 36,
    this.shape = AppAvatarShape.circle,
    this.status,
    this.speaking = false,
    this.ringColor,
    this.semanticLabel,
  });

  final String name;

  /// Null while the profile this avatar belongs to has not loaded yet, or
  /// for content with no author (a deleted account): renders as initials
  /// only, same as [AppAvatar] with no image ever passed in.
  final String? userId;
  final int? avatarUpdatedAt;
  final double size;
  final AppAvatarShape shape;
  final AppPresence? status;
  final bool speaking;
  final Color? ringColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = userId;
    ImageProvider? image;
    if (id != null) {
      final bytes = ref
          .watch(avatarBytesProvider((userId: id, updatedAt: avatarUpdatedAt)))
          .valueOrNull;
      if (bytes != null) image = MemoryImage(bytes);
    }
    return AppAvatar(
      name: name,
      image: image,
      size: size,
      shape: shape,
      status: status,
      speaking: speaking,
      ringColor: ringColor,
      semanticLabel: semanticLabel,
    );
  }
}

/// [UserAvatar], for a caller that holds only an author id and a display
/// name (a message row, a pinned-message tile) rather than the profile it
/// rides on: resolves [userProfileProvider] first for the avatar cache key,
/// then renders exactly like [UserAvatar] once that resolves.
class AuthorAvatar extends ConsumerWidget {
  const AuthorAvatar({
    super.key,
    required this.name,
    required this.userId,
    this.size = 36,
    this.shape = AppAvatarShape.circle,
  });

  final String name;

  /// Null for a deleted or never-attributed author: no lookup to make, so
  /// this renders straight to initials.
  final String? userId;
  final double size;
  final AppAvatarShape shape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = userId;
    final profile =
        id == null ? null : ref.watch(userProfileProvider(id)).valueOrNull;
    return UserAvatar(
      name: name,
      userId: id,
      avatarUpdatedAt: profile?.avatarUpdatedAt,
      size: size,
      shape: shape,
    );
  }
}
