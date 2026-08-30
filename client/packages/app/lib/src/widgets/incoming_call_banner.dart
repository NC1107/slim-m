// SPDX-License-Identifier: Apache-2.0
/// The app-wide incoming-DM-call banner.
///
/// Mounted once, above the whole shell in `HomeShell.build`, in flow rather
/// than as an overlay - `docs/design/desktop-vs-mobile.md` rule 6 ("status
/// the user did not ask for -> banner: it pushes content, never overlays
/// it"). Reaches every pane and every width the same way `VoiceStripIndicator`
/// reaches an ongoing call elsewhere: a ring is a `VIEW_CHANNEL`-gated live
/// frame for a DM this account is already a party to, so nothing here needs
/// to know which screen is active to be allowed to show it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/dm_call_ring_controller.dart';
import '../providers/user_profiles.dart';
import '../screens/dm_call_pane.dart';
import '../screens/voice_call_controls.dart' show CallDockButton;
import 'floating_dock_card.dart';
import 'user_avatar.dart';

class IncomingCallBanner extends ConsumerWidget {
  const IncomingCallBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ring = ref.watch(
      dmCallRingControllerProvider.select((s) => s.incoming),
    );
    if (ring == null) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      minimum: const EdgeInsets.only(top: AppSpacing.s12),
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.s12,
          right: AppSpacing.s12,
          bottom: AppSpacing.s12,
        ),
        child: FloatingDockCard(rows: [_IncomingCallRow(ring: ring)]),
      ),
    );
  }
}

class _IncomingCallRow extends ConsumerWidget {
  const _IncomingCallRow({required this.ring});

  final IncomingDmCallRing ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final profile = ref.watch(userProfileProvider(ring.callerId)).valueOrNull;
    final name = profile?.displayName ?? 'Someone';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            name: name,
            userId: profile?.id,
            avatarUpdatedAt: profile?.avatarUpdatedAt,
            size: 32,
          ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: AppWeights.medium,
                  ),
                ),
                Text(
                  'Incoming call',
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          CallDockButton(
            icon: AppIcons.leaveCall,
            tooltip: 'Decline',
            active: false,
            destructive: true,
            onPressed: () => unawaited(
              ref.read(dmCallRingControllerProvider.notifier).decline(ring),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          CallDockButton(
            icon: AppIcons.startCall,
            tooltip: 'Accept',
            active: true,
            onPressed: () => _accept(ref),
          ),
        ],
      ),
    );
  }

  void _accept(WidgetRef ref) {
    ref.read(dmCallRingControllerProvider.notifier).dismissIncoming();
    ref.read(dmCallOpenProvider.notifier).state = ring.channelId;
  }
}
