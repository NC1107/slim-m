// SPDX-License-Identifier: Apache-2.0
/// One member, and everything you can do about them.
///
/// Anchored popover on a pointer layout, bottom sheet on a compact one, from
/// the same content: the member pane, a message author, and the call roster
/// all open this rather than each growing its own menu.
///
/// The sections compose in a fixed order - header, call, social verbs,
/// moderation, block - and a section you have no rights or context for is
/// *absent* rather than present-and-disabled, which is what keeps a plain
/// member's popover to two verbs instead of a wall of greyed rows.
///
/// Everything in the call section is local to this listener and never
/// reaches the room; anything room-visible would sit under the moderation
/// label, which is why "Mute for me" is named the way it is.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/dms.dart';
import '../providers/providers.dart';
import '../providers/voice_controller.dart';
import '../routing/routes.dart';
import 'member_actions.dart';
import 'user_avatar.dart';

/// The popover's width on a pointer layout, from the design.
const double _popoverWidth = 280;

/// Opens the profile surface for [profile], anchored to [anchor] where there
/// is a pointer and presented as a sheet where there is not.
///
/// [anchor] is the widget the popover hangs off; the caller passes its own
/// context so the popover lands beside the row that was clicked rather than
/// in the middle of the window.
Future<void> showMemberProfile(
  BuildContext anchor,
  WidgetRef ref, {
  required api.UserProfile profile,
  required AppPresence status,
  String? mentionChannelName,
}) {
  final compact = MediaQuery.sizeOf(anchor).width < kCompactWidth;
  if (compact) {
    return showModalBottomSheet<void>(
      context: anchor,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: MemberProfileBody(
          profile: profile,
          status: status,
          mentionChannelName: mentionChannelName,
          compact: true,
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  final origin = box == null || overlay == null
      ? Offset.zero
      : box.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorSize = box?.size ?? Size.zero;

  return showGeneralDialog<void>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.reduced(anchor, AppMotion.base),
    pageBuilder: (context, _, __) => _AnchoredPopover(
      origin: origin,
      anchorSize: anchorSize,
      child: MemberProfileBody(
        profile: profile,
        status: status,
        mentionChannelName: mentionChannelName,
        compact: false,
        onDone: () => Navigator.of(context).pop(),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.entrance,
        reverseCurve: AppMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (1 - curved.value) * 8),
            child: child,
          ),
          child: child,
        ),
      );
    },
  );
}

/// Places the popover beside its anchor, kept inside the viewport rather than
/// running off an edge - the same clamping the message context menu does.
class _AnchoredPopover extends StatelessWidget {
  const _AnchoredPopover({
    required this.origin,
    required this.anchorSize,
    required this.child,
  });

  final Offset origin;
  final Size anchorSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context) + const EdgeInsets.all(8);
    // Prefers the anchor's right side, flipping left when it would overhang.
    final left = (origin.dx + anchorSize.width + 8 + _popoverWidth > view.width)
        ? (origin.dx - _popoverWidth - 8).clamp(padding.left, view.width)
        : (origin.dx + anchorSize.width + 8).clamp(padding.left, view.width);
    final top = origin.dy.clamp(
      padding.top,
      (view.height - padding.bottom - 120).clamp(padding.top, view.height),
    );
    return Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: view.height - top - padding.bottom,
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ],
    );
  }
}

/// The sections themselves, shared by both presentations.
class MemberProfileBody extends ConsumerWidget {
  const MemberProfileBody({
    super.key,
    required this.profile,
    required this.status,
    required this.compact,
    required this.onDone,
    this.mentionChannelName,
  });

  final api.UserProfile profile;
  final AppPresence status;

  /// Named so "Mention in #general" can say which channel; absent where
  /// there is no channel in view, and the row goes with it.
  final String? mentionChannelName;

  final bool compact;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull;
    final isSelf = me?.id == profile.id;
    final voice = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);
    // The call section exists only while you share a call: it is about your ears in this room, not the person.
    final inCallTogether =
        voice.state == VoiceSessionState.connected &&
        voice.participants.any((p) => p.identity == profile.id && !p.isLocal);

    void run(Future<void> Function() action) {
      onDone();
      unawaited(action());
    }

    final rows = <Widget>[
      _Header(
        profile: profile,
        status: status,
        isSelf: isSelf,
        inCallTogether: inCallTogether,
      ),
      const AppMenuDivider(),

      if (inCallTogether) ...[
        _LocalAudioSection(profile: profile, controller: controller),
        const AppMenuDivider(),
      ],

      if (isSelf) ...[
        AppMenuItem(
          label: 'Profile settings',
          leading: AppIcons.settings,
          onTap: () {
            onDone();
            context.push(Routes.personalSettings);
          },
        ),
      ] else ...[
        AppMenuItem(
          label: 'Message',
          leading: AppIcons.send,
          onTap: () => run(() async {
            final channelId = await openDirectMessage(ref, profile.id);
            if (context.mounted) context.go(Routes.channel(channelId));
          }),
        ),
        if (mentionChannelName != null)
          AppMenuItem(
            label: 'Mention in #$mentionChannelName',
            leading: AppIcons.hash,
            onTap: () {
              onDone();
              ref.read(pendingMentionProvider.notifier).state =
                  profile.username;
            },
          ),
      ],

      if (!isSelf) ...[
        const AppMenuDivider(),
        AppMenuItem(
          label: 'Report user',
          leading: AppIcons.report,
          onTap: () => run(() => reportMember(context, ref, profile)),
        ),
        AppMenuItem(
          label: 'Block',
          leading: AppIcons.revoke,
          tone: AppMenuItemTone.danger,
          onTap: () => run(() => blockMember(context, ref, profile)),
        ),
      ],
    ];

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s8,
          0,
          AppSpacing.s8,
          AppSpacing.s8,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      );
    }
    return AppMenu(width: _popoverWidth, children: rows);
  }
}

/// Avatar, name, role badge, and the presence word beside its dot - never
/// the dot alone, which is the same rule the member pane follows.
class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.status,
    required this.isSelf,
    required this.inCallTogether,
  });

  final api.UserProfile profile;
  final AppPresence status;
  final bool isSelf;
  final bool inCallTogether;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final badge = profile.roles.isEmpty ? null : profile.roles.first;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        children: [
          UserAvatar(
            userId: profile.id,
            avatarUpdatedAt: profile.avatarUpdatedAt,
            name: profile.displayName,
            size: 44,
            speaking: inCallTogether,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: AppWeights.semi,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: AppSpacing.s8),
                      AppBadge(variant: AppBadgeVariant.role, label: badge),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    AppStatusDot(status: status),
                    const SizedBox(width: AppSpacing.s8),
                    Flexible(
                      child: Text(
                        isSelf
                            ? '${_presenceWord(status)} - you'
                            : _presenceWord(status),
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _presenceWord(AppPresence status) => switch (status) {
  AppPresence.online => 'online',
  AppPresence.away => 'away',
  AppPresence.dnd => 'do not disturb',
  AppPresence.offline => 'offline',
  AppPresence.hidden => 'appearing offline',
};

/// What this listener can do about hearing them, all of it local.
///
/// The design's 0-200% volume slider is not here: livekit_client 2.8.1
/// exposes no per-participant gain, only whether a track plays at all, so a
/// slider would be a control that does nothing between its ends. The mute
/// half is real and ships; the slider waits for the capability.
class _LocalAudioSection extends StatelessWidget {
  const _LocalAudioSection({required this.profile, required this.controller});

  final api.UserProfile profile;
  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    final muted = controller.isLocallyMuted(profile.id);
    return AppMenuItem(
      label: muted ? 'Unmute for me' : 'Mute for me',
      leading: muted ? AppIcons.micOff : AppIcons.mic,
      selected: muted,
      onTap: () => controller.setLocallyMuted(profile.id, !muted),
    );
  }
}
