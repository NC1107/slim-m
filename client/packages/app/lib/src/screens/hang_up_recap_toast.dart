// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The "Call ended" toast, owned by the shell so it fires wherever the hang-up
/// happens: the call screen, the rail footer, the strip or the tray.
///
/// It used to live in `VoiceScreen`, which only exists while the call's own
/// channel is on screen, so leaving from anywhere else showed nothing.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/toasts.dart';
import '../providers/voice_flags.dart';
import '../routing/breakpoints.dart';
import '../widgets/call_recap_card.dart' show formatCallDuration;
import 'voice_screen.dart' show recapForChannel;

/// Toasts the recap of a call that just ended, unless the recap card already
/// says it: a wide layout with the call's own channel on screen.
///
/// Call from a build method; the listener is replaced on every rebuild, so
/// [selectedChannelId] is always the channel currently on screen.
void listenForHangUpRecap(
  BuildContext context,
  WidgetRef ref, {
  required String? selectedChannelId,
}) {
  final compact = LayoutClass.of(context) == LayoutClass.compact;
  ref.listen<VoiceFlags>(voiceFlagsProvider, (before, now) {
    final left = now.justLeftChannelId;
    if (left == null || now.justLeftAt == null) return;
    if (before?.justLeftAt == now.justLeftAt) return;
    final recap = recapForChannel(now, left);
    if (recap == null || !recap.isWorthShowing) return;
    if (!compact && selectedChannelId == left) return;
    ref
        .read(toastsProvider.notifier)
        .show(
          'Call ended - ${formatCallDuration(recap.duration)}.',
          severity: AppToastSeverity.success,
        );
  });
}
