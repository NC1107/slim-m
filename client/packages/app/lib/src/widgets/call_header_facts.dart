// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The call's identity strip: where it is, which mode, how many and how long.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/channel_by_id_provider.dart';
import '../providers/voice_controller.dart';
import 'call_participant_tiles.dart';

/// Channel name, then [mode] when the canvas is open, then count and timer.
///
/// Both the call stage and the canvas pane draw this, so a call reads the same
/// wherever it is shown. Count and timer are micro mono with tabular figures
/// so the digits do not move as the timer runs.
class CallHeaderLine extends ConsumerWidget {
  const CallHeaderLine({
    super.key,
    required this.channelId,
    this.mode,
    this.leading,
  });

  final String channelId;
  final String? mode;
  final Widget? leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = ref.watch(voiceControllerProvider);
    final name = ref.watch(channelByIdProvider(channelId)).valueOrNull?.name;
    final inThisCall = voice.channelId == channelId;
    final title = [if (name != null && name.isNotEmpty) name, ?mode].join(', ');
    final facts = AppText.micro.copyWith(
      color: tokens.textSecondary,
      fontFamily: AppFonts.mono,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        ?leading,
        Flexible(
          child: Semantics(
            container: true,
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.medium,
              ),
            ),
          ),
        ),
        if (inThisCall && voice.state == VoiceSessionState.connected) ...[
          const SizedBox(width: AppSpacing.s12),
          Text('${voice.participants.length} in call', style: facts),
          if (voice.connectedAt != null) ...[
            Text(' · ', style: facts),
            CallDuration(since: voice.connectedAt!, style: facts),
          ],
        ],
      ],
    );
  }
}
