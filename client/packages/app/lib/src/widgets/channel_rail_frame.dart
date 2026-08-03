// SPDX-License-Identifier: Apache-2.0
/// The rail's fixed top and bottom bars: the Space header (with its menu)
/// and the signed-in user's footer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/member_presence.dart';
import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import '../providers/sync_controller.dart';
import '../providers/voice_controller.dart';
import '../routing/breakpoints.dart';
import '../routing/routes.dart';
import 'presence_menu.dart';
import 'rail_call_summary.dart';
import 'space_menu_button.dart';

/// Whether this rail has content beside it, so its own right edge is never
/// the physical screen edge: true at every width the app shows it beside a
/// conversation, false for the one compact case where it fills the screen.
bool _railHasNeighbour(BuildContext context) =>
    LayoutClass.of(context).showsBothPanes;

/// The server's own identity, for the header's name line. Real endpoint;
/// there is no separate per-deployment "workspace name" concept, so this is
/// `/version`'s `name`.
final serverInfoProvider = FutureProvider.autoDispose<api.Version>(
  (ref) => ref.watch(apiProvider).version(),
);

/// The subtitle carries this build's version ([appInfoProvider], never the
/// server's own), leaving the name line its room for a long Space name.
class RailHeader extends ConsumerWidget {
  const RailHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final server = ref.watch(serverInfoProvider);
    final members = ref.watch(membersProvider);
    final version = ref.watch(appInfoProvider).valueOrNull?.version ?? '';
    // The decoration bleeds to the screen edge while [SafeArea] insets only
    // the content, so the rail's own colour fills the status-bar strip.
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SafeArea(
        bottom: false,
        // Right is only the physical edge when nothing sits beside the rail.
        right: !_railHasNeighbour(context),
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.valueOrNull?.name ?? 'slim-m',
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: AppWeights.semi,
                        ),
                      ),
                      Text(
                        [
                          members.maybeWhen(
                            data: (list) =>
                                '${list.length} members · self-hosted',
                            orElse: () => 'self-hosted',
                          ),
                          if (version.isNotEmpty) 'v$version',
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: AppText.micro.copyWith(
                          color: tokens.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SpaceMenuButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says plainly whether messages are arriving. Silently going stale is worse
/// than admitting the connection dropped; unchanged from the shell this rail
/// replaces, since the design has no equivalent state to model it on.
class RailConnectionBar extends ConsumerWidget {
  const RailConnectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Offline (messages have stopped) carries the warn tone; connecting is transient and stays neutral.
    final (label, icon, color) = switch (status) {
      SyncStatus.connecting => (
        'Connecting',
        AppIcons.pending,
        tokens.textSecondary,
      ),
      SyncStatus.offline => (
        'Offline, retrying',
        AppIcons.retry,
        tokens.warnText,
      ),
      SyncStatus.live => ('', AppIcons.info, tokens.textSecondary),
    };

    // One AnimatedSize across both states: the banner pushes content by its
    // height (motion spec 08), growing and shrinking over the panel duration
    // instead of jumping the rail's footer around.
    return AnimatedSize(
      duration: AppMotion.reducedSize(context, AppMotion.base),
      curve: AppMotion.entrance,
      alignment: Alignment.topCenter,
      child: status == SyncStatus.live
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s8,
              ),
              decoration: BoxDecoration(
                color: status == SyncStatus.offline ? tokens.warnSoft : null,
                border: Border(top: BorderSide(color: tokens.borderSubtle)),
              ),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    Icon(icon, size: AppSizes.icon16, color: color),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        label,
                        style: AppText.caption.copyWith(color: color),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class RailUserFooter extends ConsumerWidget {
  const RailUserFooter({super.key, this.activeChannelId});

  /// The channel currently shown beside or instead of this rail. A call
  /// already live in that channel has its own full call UI, so the footer's
  /// call-elsewhere row (name, duration, leave) is gated on this; mic and
  /// deafen are not, since they control whichever call is live regardless of
  /// which channel is on screen.
  final String? activeChannelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final me = ref.watch(meProvider);
    final syncStatus = ref.watch(syncControllerProvider);
    final visibility = ref.watch(presenceVisibilityDisplayProvider);
    final voice = ref.watch(voiceControllerProvider);
    final voiceController = ref.read(voiceControllerProvider.notifier);
    final inCall = voice.state == VoiceSessionState.connected;
    // A call in the channel already on screen has its own full call UI.
    final callChannelId = voice.channelId;
    final inCallElsewhere =
        inCall && callChannelId != null && callChannelId != activeChannelId;

    // A disconnected device reports its connection instead of the chosen
    // status: claiming "online" while nothing is arriving would be a lie.
    final (statusLabel, presence) = switch (syncStatus) {
      SyncStatus.live => presenceDisplayOf(visibility),
      SyncStatus.connecting => ('connecting', AppPresence.away),
      SyncStatus.offline => ('offline', AppPresence.offline),
    };

    // Mirrors [RailHeader]: the raised bar and its top border bleed to the
    // screen edge while [SafeArea] lifts the content off the home indicator.
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        right: !_railHasNeighbour(context),
        child: Padding(
          key: const Key('rail-footer-padding'),
          // Slimmed from fromLTRB(12, 8, 10, 8) on the owner's own request:
          // AppSpacing has no step between s4 and s8, so s4 is the nearest
          // real reduction rather than a new number.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s4,
          ),
          // The call-elsewhere row grows the footer rather than sharing the identity row's width; see RailCallSummary's own doc for why.
          child: AnimatedSize(
            duration: AppMotion.reducedSize(context, AppMotion.base),
            curve: AppMotion.entrance,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    PresenceMenuButton(presence: presence),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me.valueOrNull?.displayName ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: AppText.ui.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: AppWeights.medium,
                              height: 1.25,
                            ),
                          ),
                          Text(
                            statusLabel,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.micro.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: voice.microphoneEnabled
                          ? AppIcons.mic
                          : AppIcons.micOff,
                      semanticLabel: voice.microphoneEnabled
                          ? 'Mute'
                          : 'Unmute',
                      tooltip: inCall ? null : 'Not in a call',
                      onPressed: inCall
                          ? voiceController.toggleMicrophone
                          : null,
                    ),
                    // Same icon either way, the toggle carried by `active`:
                    // there is no dedicated "deafened" glyph in AppIcons.
                    AppIconButton(
                      icon: AppIcons.headphones,
                      semanticLabel: voice.deafened ? 'Undeafen' : 'Deafen',
                      active: voice.deafened,
                      tooltip: inCall ? null : 'Not in a call',
                      onPressed: inCall ? voiceController.toggleDeafen : null,
                    ),
                    AppIconButton(
                      icon: AppIcons.settings,
                      semanticLabel: 'Personal settings',
                      onPressed: () => context.push(Routes.personalSettings),
                    ),
                  ],
                ),
                if (inCallElsewhere) ...[
                  const SizedBox(height: 6),
                  RailCallSummary(
                    channelId: callChannelId,
                    connectedAt: voice.connectedAt,
                    screenSharing: voice.screenSharing,
                    onLeave: voiceController.leave,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
