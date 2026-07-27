// SPDX-License-Identifier: Apache-2.0
/// The rail's fixed top and bottom bars: the server header (with its menu)
/// and the signed-in user's footer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import '../providers/sync_controller.dart';
import '../providers/voice_controller.dart';
import '../routing/routes.dart';
import 'member_pane.dart';
import 'presence_menu.dart';

/// The server's own identity, for the header's name line. Real endpoint;
/// there is no separate per-deployment "workspace name" concept, so this is
/// `/version`'s `name`.
final serverInfoProvider = FutureProvider.autoDispose<api.Version>(
  (ref) => ref.watch(apiProvider).version(),
);

class RailHeader extends ConsumerWidget {
  const RailHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final server = ref.watch(serverInfoProvider);
    final members = ref.watch(membersProvider);

    // The decoration bleeds to the screen edge while [SafeArea] insets only
    // the content, so the rail's own colour fills the status-bar strip.
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SafeArea(
        bottom: false,
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
                        members.maybeWhen(
                          data: (list) =>
                              '${list.length} members · self-hosted',
                          orElse: () => 'self-hosted',
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: AppText.micro.copyWith(
                          color: tokens.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const _ServerMenuButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerMenuButton extends StatefulWidget {
  const _ServerMenuButton();

  @override
  State<_ServerMenuButton> createState() => _ServerMenuButtonState();
}

class _ServerMenuButtonState extends State<_ServerMenuButton> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        // Positioned so the follower sizes to its content: an overlay child is
        // otherwise laid out against the whole screen, which a Column fills.
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: TapRegion(
              onTapOutside: (_) => _controller.hide(),
              child: AppMenu(
                width: 200,
                children: [
                  AppMenuItem(
                    label: 'Settings',
                    leading: AppIcons.settings,
                    onTap: () {
                      _controller.hide();
                      context.go(Routes.settings);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        child: AppIconButton(
          icon: AppIcons.chevronDown,
          semanticLabel: 'Server menu',
          onPressed: _controller.toggle,
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
    if (status == SyncStatus.live) return const SizedBox.shrink();

    final label = switch (status) {
      SyncStatus.connecting => 'Connecting',
      SyncStatus.offline => 'Offline, retrying',
      SyncStatus.live => '',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(label,
            style: AppText.caption.copyWith(color: tokens.textSecondary)),
      ),
    );
  }
}

class RailUserFooter extends ConsumerWidget {
  const RailUserFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final me = ref.watch(meProvider);
    final syncStatus = ref.watch(syncControllerProvider);
    final visibility = ref.watch(presenceVisibilityDisplayProvider);
    final voice = ref.watch(voiceControllerProvider);
    final voiceController = ref.read(voiceControllerProvider.notifier);
    final inCall = voice.state == VoiceSessionState.connected;

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
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            child: Row(
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
                        style:
                            AppText.micro.copyWith(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                AppIconButton(
                  icon:
                      voice.microphoneEnabled ? AppIcons.mic : AppIcons.micOff,
                  semanticLabel: voice.microphoneEnabled ? 'Mute' : 'Unmute',
                  tooltip: inCall ? null : 'Not in a call',
                  onPressed: inCall ? voiceController.toggleMicrophone : null,
                ),
                // Same icon either way, the toggle carried by `active`: there
                // is no dedicated "deafened" glyph in AppIcons.
                AppIconButton(
                  icon: AppIcons.headphones,
                  semanticLabel: voice.deafened ? 'Undeafen' : 'Deafen',
                  active: voice.deafened,
                  tooltip: inCall ? null : 'Not in a call',
                  onPressed: inCall ? voiceController.toggleDeafen : null,
                ),
                AppIconButton(
                  icon: AppIcons.settings,
                  semanticLabel: 'Settings',
                  onPressed: () => context.go(Routes.settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
