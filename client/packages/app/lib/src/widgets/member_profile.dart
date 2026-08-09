// SPDX-License-Identifier: Apache-2.0
/// One member, and everything you can do about them.
///
/// Anchored popover on a pointer layout, bottom sheet on a compact one, from
/// the same content: the member pane, a message author, and the call roster
/// all open this rather than each growing its own menu.
///
/// The sections compose in a fixed order - header, timeout badge, call,
/// social verbs, moderation, block - and a section you have no rights or
/// context for is *absent* rather than present-and-disabled, which is what
/// keeps a plain member's popover to two verbs instead of a wall of greyed
/// rows.
///
/// Everything in the call section is local to this listener and never reaches
/// the room; anything room-visible sits under the MODERATION label, which is
/// why "Mute for me" is named the way it is and why a timeout is not next to
/// it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../providers/blocks_controller.dart';
import '../providers/dms.dart';
import '../providers/member_presence.dart' show membersProvider;
import '../providers/providers.dart';
import '../providers/voice_controller.dart';
import '../routing/routes.dart';
import 'app_snackbar.dart';
import 'confirm_dialog.dart';
import 'member_actions.dart';
import 'member_profile_popover.dart';
import 'member_profile_sections.dart';
import 'member_roles_sheet.dart';
import 'run_guarded.dart';

/// The popover's width on a pointer layout, from the design.
const double _popoverWidth = 280;

/// Opens the profile surface for [profile], anchored to [anchor] where there
/// is a pointer and presented as a sheet where there is not.
///
/// [anchor] is the widget the popover hangs off; the caller passes its own
/// context so the popover lands beside the row that was clicked rather than
/// in the middle of the window.
///
/// On compact width the roster this popover can open from lives in a
/// `Scaffold.endDrawer`, whose open state lives on the `ScaffoldState` and
/// outlives a `go_router` navigation - the shell's `Scaffold` is reused
/// rather than rebuilt. [Scaffold.maybeOf] is read from [anchor] here, before
/// anything else runs, so a navigating action can close it as part of
/// itself; see [MemberProfileBody.memberPaneScaffold].
Future<void> showMemberProfile(
  BuildContext anchor,
  WidgetRef ref, {
  required api.UserProfile profile,
  required AppPresence status,
  String? mentionChannelName,
  String? callChannelName,
}) {
  // Read before anything pops: a popped context has no navigator above it.
  final host = Navigator.of(anchor, rootNavigator: true).context;
  final compact = MediaQuery.sizeOf(anchor).width < kCompactWidth;
  final memberPaneScaffold = Scaffold.maybeOf(anchor);

  if (compact) {
    // Its own controller reads the platform's own reduce-motion feature, never this app's MotionOverride; see sheet.dart's library doc.
    final noAnimation = AppMotion.isReduced(anchor)
        ? AnimationStyle.noAnimation
        : null;
    return showModalBottomSheet<void>(
      context: anchor,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: noAnimation,
      builder: (context) => SafeArea(
        top: false,
        child: MemberProfileBody(
          profile: profile,
          status: status,
          mentionChannelName: mentionChannelName,
          callChannelName: callChannelName,
          compact: true,
          host: host,
          memberPaneScaffold: memberPaneScaffold,
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
    pageBuilder: (context, _, __) => AnchoredMemberPopover(
      origin: origin,
      anchorSize: anchorSize,
      width: _popoverWidth,
      child: MemberProfileBody(
        profile: profile,
        status: status,
        mentionChannelName: mentionChannelName,
        callChannelName: callChannelName,
        compact: false,
        host: host,
        memberPaneScaffold: memberPaneScaffold,
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

/// The sections themselves, shared by both presentations.
class MemberProfileBody extends ConsumerStatefulWidget {
  const MemberProfileBody({
    super.key,
    required this.profile,
    required this.status,
    required this.compact,
    required this.onDone,
    this.mentionChannelName,
    this.callChannelName,
    this.host,
    this.memberPaneScaffold,
  });

  final api.UserProfile profile;
  final AppPresence status;

  /// Named so "Mention in #general" can say which channel; absent where
  /// there is no channel in view, and the row goes with it.
  final String? mentionChannelName;

  /// The voice channel shared with this member, so the header can say "in
  /// lounge with you" instead of restating a presence everyone can see.
  final String? callChannelName;

  final bool compact;
  final VoidCallback onDone;

  /// A context that outlives this surface, for anything that opens a second
  /// one after this closes. Without it a follow-up sheet looks a navigator up
  /// through a context whose route has already popped, which throws.
  final BuildContext? host;

  /// The compact roster's endDrawer, if this popover opened from it. Closing
  /// it is safe to call unconditionally: [ScaffoldState.closeEndDrawer] is a
  /// no-op with nothing open, and null means there was never a drawer here.
  final ScaffoldState? memberPaneScaffold;

  @override
  ConsumerState<MemberProfileBody> createState() => _MemberProfileBodyState();
}

class _MemberProfileBodyState extends ConsumerState<MemberProfileBody>
    with GuardedActionState<MemberProfileBody> {
  api.UserProfile get _profile {
    // Live, so a timeout applied here repaints as the badge without reopening.
    final live = ref
        .watch(membersProvider)
        .valueOrNull
        ?.where((m) => m.id == widget.profile.id)
        .firstOrNull;
    return live ?? widget.profile;
  }

  Future<void> _timeOut(Duration duration) async {
    final ok = await guard(
      whatFailed: 'time this member out',
      action: () => ref
          .read(apiProvider)
          .timeOutMember(userId: widget.profile.id, duration: duration),
    );
    if (ok && mounted) ref.invalidate(membersProvider);
  }

  Future<void> _liftTimeout() async {
    final ok = await guard(
      whatFailed: 'lift the timeout',
      action: () => ref.read(apiProvider).liftMemberTimeout(widget.profile.id),
    );
    if (ok && mounted) ref.invalidate(membersProvider);
  }

  /// [channelId] is the call this member shares with the caller right now,
  /// captured before the popover is dismissed for the same reason [_remove]
  /// captures its container: a kick from a room nobody is in means nothing.
  Future<void> _eject(
    BuildContext host,
    ProviderContainer container,
    String channelId,
  ) async {
    final name = widget.profile.displayName;
    final confirmed = await confirmDangerousAction(
      host,
      title: 'Eject $name from this call?',
      // A live token still works after this: says so, not just "removed".
      message:
          'They will be disconnected from the call right now. Nothing stops '
          'them rejoining - time them out or remove them from the Space for '
          'something that sticks.',
      confirmLabel: 'Eject',
    );
    if (!confirmed) return;
    final failure = await runGuarded(
      whatFailed: 'eject $name from the call',
      action: () => container
          .read(apiProvider)
          .kickVoiceParticipant(channelId, widget.profile.id),
    );
    if (failure != null && host.mounted) {
      showAppSnackbar(host, failure);
    }
  }

  /// [container] must be captured before the popover is dismissed: this
  /// awaits a confirmation dialog first, and by the time it answers `ref` is
  /// tied to a disposed element, exactly the bug this whole file exists to
  /// avoid.
  Future<void> _remove(BuildContext host, ProviderContainer container) async {
    final name = widget.profile.displayName;
    final confirmed = await confirmDangerousAction(
      host,
      title: 'Remove $name from this Space?',
      // Says what it does and does not do; "remove" misleads in both directions.
      message:
          'They will be signed out and cannot sign in again, and any '
          'invites they handed out stop working. Everything they wrote stays, '
          'still shown as theirs. You can let them back in later.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await runGuarded(
      whatFailed: 'remove $name',
      action: () =>
          container.read(apiProvider).removeMember(userId: widget.profile.id),
    ).then((failure) {
      if (failure == null) {
        container.invalidate(membersProvider);
      } else if (host.mounted) {
        showAppSnackbar(host, failure);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final me = ref.watch(meProvider).valueOrNull;
    final isSelf = me?.id == profile.id;
    final mine = ref.watch(myPermissionsProvider);
    final voice = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);
    final host = widget.host ?? context;

    // The call section exists only while you share a call: it is about your ears in this room, not the person.
    final inCallTogether =
        voice.state == VoiceSessionState.connected &&
        voice.participants.any((p) => p.identity == profile.id && !p.isLocal);

    final canTimeOut = !isSelf && mine.hasPermission(Perm.kickMembers);
    final canRemove = !isSelf && mine.hasPermission(Perm.banMembers);
    final canManageRoles = !isSelf && mine.hasPermission(Perm.manageRoles);
    // Needs a room to evict them from, not just the bit; the call section above already answers that.
    final canEject =
        !isSelf &&
        inCallTogether &&
        voice.channelId != null &&
        mine.hasPermission(Perm.kickMembers);
    final showModeration =
        canTimeOut || canRemove || canManageRoles || canEject;

    // Captured before onDone, whose Navigator.pop disposes this element.
    void run(Future<void> Function(ProviderContainer container) action) {
      final container = ProviderScope.containerOf(context, listen: false);
      widget.onDone();
      unawaited(action(container));
    }

    final rows = <Widget>[
      MemberProfileHeader(
        profile: profile,
        status: widget.status,
        isSelf: isSelf,
        inCallTogether: inCallTogether,
        callChannelName: widget.callChannelName,
      ),

      if (profile.timedOutUntil != null)
        MemberTimeoutBadge(
          until: profile.timedOutUntil!,
          onLift: canTimeOut ? _liftTimeout : null,
        ),

      const AppMenuDivider(),

      if (inCallTogether) ...[
        MemberLocalAudioSection(identity: profile.id, controller: controller),
        const AppMenuDivider(),
      ],

      if (isSelf) ...[
        AppMenuItem(
          label: 'Profile settings',
          leading: AppIcons.settings,
          onTap: () {
            widget.onDone();
            widget.memberPaneScaffold?.closeEndDrawer();
            host.push(Routes.personalSettings);
          },
        ),
      ] else ...[
        AppMenuItem(
          label: 'Message',
          leading: AppIcons.send,
          onTap: () {
            widget.memberPaneScaffold?.closeEndDrawer();
            run((container) async {
              final channelId = await openDirectMessage(container, profile.id);
              if (host.mounted) host.go(Routes.channel(channelId));
            });
          },
        ),
        if (widget.mentionChannelName != null)
          AppMenuItem(
            label: 'Mention in #${widget.mentionChannelName}',
            leading: AppIcons.hash,
            onTap: () {
              widget.onDone();
              ref.read(pendingMentionProvider.notifier).state =
                  profile.username;
            },
          ),
      ],

      if (showModeration) ...[
        const AppMenuDivider(),
        const AppMenuLabel('Moderation'),
        if (canManageRoles)
          AppMenuItem(
            label: 'Roles...',
            leading: AppIcons.shield,
            submenu: true,
            onTap: () {
              widget.onDone();
              unawaited(showMemberRolesSheet(host, profile.id));
            },
          ),
        // Absent while one is in force: the badge above already carries it.
        if (canTimeOut && profile.timedOutUntil == null)
          TimeoutDurationChips(onChosen: _timeOut),
        if (canEject)
          AppMenuItem(
            label: 'Eject from call...',
            leading: AppIcons.leaveCall,
            tone: AppMenuItemTone.danger,
            onTap: () {
              final container = ProviderScope.containerOf(
                context,
                listen: false,
              );
              final channelId = voice.channelId!;
              widget.onDone();
              unawaited(_eject(host, container, channelId));
            },
          ),
        if (canRemove)
          AppMenuItem(
            label: 'Remove from Space...',
            leading: AppIcons.signOut,
            tone: AppMenuItemTone.danger,
            onTap: () {
              final container = ProviderScope.containerOf(
                context,
                listen: false,
              );
              widget.onDone();
              unawaited(_remove(host, container));
            },
          ),
      ],

      if (!isSelf) ...[
        const AppMenuDivider(),
        AppMenuItem(
          label: 'Report user',
          leading: AppIcons.report,
          onTap: () =>
              run((container) => reportMember(host, container, profile)),
        ),
        // Offering Block again to a blocked member reads as the block failing.
        if (ref.watch(blocksProvider).contains(profile.id))
          AppMenuItem(
            label: 'Unblock',
            leading: AppIcons.revoke,
            onTap: () =>
                run((container) => unblockMember(host, container, profile)),
          )
        else
          AppMenuItem(
            label: 'Block',
            leading: AppIcons.revoke,
            tone: AppMenuItemTone.danger,
            onTap: () =>
                run((container) => blockMember(host, container, profile)),
          ),
      ],

      if (actionError != null)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: AppErrorState(
            message: actionError!,
            onDismiss: clearActionError,
          ),
        ),
    ];

    if (widget.compact) {
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
