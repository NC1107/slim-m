// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The per-channel canvas object cap control, on the Space performance
/// screen. Split from `performance_screen.dart`, which is at its file-size
/// ceiling; the two share the screen but not a file, the same split
/// `screen_share_cap_section.dart` already uses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../widgets/canvas_memory_estimate.dart';
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_section_header.dart';
import '../../widgets/success_flash.dart';

/// The per-channel canvas object cap; index-matched to the segmented options
/// below. All lie inside the server's settable range (100 to 100000), and
/// 20000 is the default a deployment keeps until an admin sets one.
const _canvasCapOptions = <(String, int)>[
  ('5,000', 5000),
  ('10,000', 10000),
  ('20,000', 20000),
  ('50,000', 50000),
];

String _formatCount(int n) {
  final digits = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// What raising or lowering [cap] actually costs, in the one real memory
/// measurement this can be grounded in - see `canvas_memory_estimate.dart`.
String canvasCapConsequence(int cap) {
  final estimate = estimateCanvasMemoryMb(cap).toStringAsFixed(1);
  final basis = canvasMemoryEstimateIsExtrapolated(cap)
      ? 'past what was actually measured, so treat this as an order of '
            'magnitude, not a guarantee'
      : 'interpolated between real measurements at 5,000 and 20,000 objects';
  return 'A channel with ${_formatCount(cap)} objects adds roughly '
      '$estimate MB of resident memory per client that opens it, on top of '
      'the bare app (Linux desktop measurements in '
      'docs/reports/perf-2026-08.md; $basis). Per-object cost is not '
      'constant there - the same report saw it vary by roughly 65% between '
      'repeat runs of the same count.';
}

/// The per-channel canvas object cap: a client-performance control that
/// applies to every viewer, independent of the analytics toggle, so it stays
/// visible and usable whether or not Space analytics recording is on.
class CanvasCapSection extends ConsumerStatefulWidget {
  const CanvasCapSection({super.key});

  @override
  ConsumerState<CanvasCapSection> createState() => _CanvasCapSectionState();
}

class _CanvasCapSectionState extends ConsumerState<CanvasCapSection>
    with GuardedActionState<CanvasCapSection> {
  bool _saving = false;
  int? _optimisticCap;

  Future<void> _setCap(int cap) async {
    setState(() {
      _saving = true;
      _optimisticCap = cap;
    });
    final ok = await guard(
      whatFailed: 'change the canvas object cap',
      action: () => ref.read(apiProvider).setSpaceCanvasObjectCap(cap),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) _optimisticCap = null;
    });
    if (ok) ref.invalidate(spaceCanvasCapProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final cap = ref.watch(spaceCanvasCapProvider);
    ref.listen(spaceCanvasCapProvider, (previous, next) {
      if (next.hasValue && !next.isLoading && _optimisticCap != null) {
        setState(() => _optimisticCap = null);
      }
    });
    final current = _optimisticCap ?? cap.valueOrNull ?? 20000;
    final selectedIndex = _canvasCapOptions.indexWhere((o) => o.$2 == current);

    return SettingsSectionCard(
      title: 'Canvas object cap',
      children: [
        Text(
          'The most objects one channel\'s canvas may hold before a new one is '
          'refused. Applies to every client: a lower cap keeps a busy canvas '
          'lighter to load and draw.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        AppSegmentedControl.inline(
          semanticLabel: 'Canvas object cap',
          options: [
            for (final option in _canvasCapOptions)
              AppSegmentedOption(label: option.$1, disabled: _saving),
          ],
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onSegmentSelected: (i) => _setCap(_canvasCapOptions[i].$2),
        ),
        const SizedBox(height: AppSpacing.s12),
        AppCallout(
          tone: AppCalloutTone.info,
          child: Text(canvasCapConsequence(current)),
        ),
        SuccessFlash(tick: successTick),
        if (actionError != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppErrorState(message: actionError!, onDismiss: clearActionError),
        ],
      ],
    );
  }
}
