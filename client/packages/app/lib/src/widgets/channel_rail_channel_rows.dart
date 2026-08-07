// SPDX-License-Identifier: Apache-2.0
/// The rail's channel rows: the manage-sheet pairing, the voice row and the
/// participant strip beneath it.
///
/// Split out of `channel_rail_sections.dart` when that file crossed the
/// 300-line review budget; the sections there own layout and permissions,
/// these own one row each.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';
import '../providers/voice_roster.dart';
import '../routing/routes.dart';
import 'context_menu_region.dart';
import 'manage_channel_sheet.dart';
import 'user_avatar.dart';
import 'voice_channel_tap.dart';

/// The right-click/long-press menu every channel row gets: opening it always,
/// managing it (rename, topic, delete) only for the caller [canManage] already
/// lets use the row's own kebab - the same gate, reused rather than repeated.
List<Widget> _channelMenuItems(
  BuildContext context,
  VoidCallback close,
  Channel channel,
  bool canManage,
) => [
  AppMenuItem(
    label: 'Open channel',
    leading: AppIcons.hash,
    onTap: () {
      close();
      context.go(Routes.channel(channel.id));
    },
  ),
  if (canManage)
    AppMenuItem(
      label: 'Manage channel...',
      leading: AppIcons.settings,
      onTap: () {
        close();
        showManageChannelSheet(context, channel);
      },
    ),
];

/// Pairs a channel row with its manage-sheet trigger, handed to
/// [AppListRow.trailingExtra] (via [row]'s own builder) rather than composed
/// as a plain sibling: a sibling sits outside the tinted container the row's
/// hover and press highlight paints into, so the highlight visibly stopped
/// short of the kebab and the row read as two pieces.
class ManagedChannelRow extends StatefulWidget {
  const ManagedChannelRow({
    super.key,
    required this.canManage,
    required this.channel,
    required this.row,
  });

  final bool canManage;
  final Channel channel;

  /// Builds the row given the kebab to place in its trailing slot, or null
  /// when [canManage] is false. Passed through unconditionally so the row
  /// itself decides where to put it (`AppListRow.trailingExtra`, alongside
  /// whatever [AppListRow.trailing] or the unread dot already occupies).
  final Widget Function(Widget? kebab) row;

  @override
  State<ManagedChannelRow> createState() => _ManagedChannelRowState();
}

class _ManagedChannelRowState extends State<ManagedChannelRow> {
  bool _hovered = false;
  bool _kebabFocused = false;

  List<Widget> _menuItems(BuildContext context, VoidCallback close) =>
      _channelMenuItems(context, close, widget.channel, widget.canManage);

  @override
  Widget build(BuildContext context) {
    if (!widget.canManage) {
      return ContextMenuRegion(
        itemsBuilder: _menuItems,
        ownsFocusNode: false,
        child: widget.row(null),
      );
    }
    // Mirrors _SectionLabel's own trailing inset so this glyph and the
    // section's add glyph share a right edge; both are AppIconButtonSize.sm.
    final touch = AppTouchTargets.of(context);
    final trailingPad = touch ? 0.0 : 4.0;

    // A persistent kebab on every row adds a column of noise to the calmest
    // part of the shell, so a pointer reveals it on row hover (or when tab
    // reaches it, so a keyboard user never focuses something invisible). The
    // slot keeps its width either way; nothing reflows. A finger has no
    // hover, so touch keeps it always visible.
    final shown = touch || _hovered || _kebabFocused;
    final kebab = Padding(
      padding: EdgeInsets.only(right: trailingPad),
      child: SizedBox(
        height: AppListRow.heightFor(context),
        child: Center(
          child: Focus(
            skipTraversal: true,
            canRequestFocus: false,
            onFocusChange: (v) => setState(() => _kebabFocused = v),
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: AppMotion.reduced(context, AppMotion.fast),
              // Hidden from the eye is not hidden from a screen reader: the
              // manage action must stay in the semantics tree while unhovered.
              alwaysIncludeSemantics: true,
              child: AppIconButton(
                icon: AppIcons.moreVertical,
                semanticLabel: 'Manage ${widget.channel.name}',
                size: AppIconButtonSize.sm,
                onPressed: () =>
                    showManageChannelSheet(context, widget.channel),
              ),
            ),
          ),
        ),
      ),
    );
    // Inside the row's trailing slot, so no combined height to float against.
    return ContextMenuRegion(
      itemsBuilder: _menuItems,
      ownsFocusNode: false,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: widget.row(kebab),
      ),
    );
  }
}

class VoiceChannelRow extends ConsumerWidget {
  const VoiceChannelRow({
    super.key,
    required this.channel,
    required this.selected,
    this.trailingExtra,
  });

  final Channel channel;
  final bool selected;

  /// The kebab [ManagedChannelRow] hands down, rendered in the same
  /// trailing slot as the participant count so both sit inside the row's
  /// own press/hover highlight rather than beside it.
  final Widget? trailingExtra;

  bool _inCall(VoiceState voice) =>
      voice.state == VoiceSessionState.connected &&
      voice.channelId == channel.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Watched here, not by the section that lays out every row, so a room event rebuilds only voice rows.
    final voice = ref.watch(voiceControllerProvider);
    final inCall = _inCall(voice);
    final iconColor = inCall
        ? tokens.accent
        : tokens.textSecondary.withValues(alpha: 0.7);

    // A joined call already has this live; an unjoined one polls for it below.
    final participants = inCall
        ? voice.participants
        : ref
                  .watch(voiceRosterProvider(channel.id))
                  .valueOrNull
                  ?.map(_asVoiceParticipant)
                  .toList(growable: false) ??
              const <VoiceParticipant>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppListRow(
          label: channel.name,
          selected: selected,
          unread: inCall,
          leading: Icon(
            AppIcons.voice,
            size: AppSizes.icon16,
            color: iconColor,
          ),
          trailing: participants.isEmpty
              ? null
              : Text(
                  '${participants.length}',
                  style: AppText.micro.copyWith(
                    color: tokens.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
          trailingExtra: trailingExtra,
          onTap: () {
            context.go(Routes.channel(channel.id));
            // A re-click of the channel already open: `VoiceScreen`'s own
            // auto-join only fires on a fresh arrival, so this is the one
            // case nothing else asks to rejoin; see voice_channel_tap.dart.
            if (voiceChannelTapShouldRejoin(
              voice: voice,
              channelId: channel.id,
              alreadySelected: selected,
            )) {
              ref.read(voiceControllerProvider.notifier).join(channel.id);
            }
          },
        ),
        if (participants.isNotEmpty)
          _ParticipantStrip(participants: participants),
      ],
    );
  }
}

/// A roster snapshot carries no live speaking or screen-share signal, only
/// who is connected, so every derived flag here is false rather than guessed.
VoiceParticipant _asVoiceParticipant(api.VoiceRosterParticipant p) =>
    VoiceParticipant(
      identity: p.userId,
      name: p.displayName,
      isSpeaking: false,
      isMuted: false,
      isLocal: false,
      isScreenSharing: false,
    );

/// Who is in a voice channel: real-time for the one the caller has joined,
/// a periodic snapshot ([voiceRosterProvider]) for every other one.
class _ParticipantStrip extends StatelessWidget {
  const _ParticipantStrip({required this.participants});

  final List<VoiceParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 2, 8, 4),
      child: Row(
        children: [
          for (final participant in participants.take(8))
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s4),
              child: AuthorAvatar(
                name: participant.name,
                userId: participant.identity,
                size: 20,
                speaking: participant.isSpeaking,
              ),
            ),
          if (participants.any((p) => p.isScreenSharing))
            Icon(AppIcons.screenShare, size: 13, color: tokens.textSecondary),
        ],
      ),
    );
  }
}
