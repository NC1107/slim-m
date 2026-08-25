// SPDX-License-Identifier: Apache-2.0
/// The screen-share resolution ceiling control on the Space analytics
/// screen. Split from `analytics_screen.dart`, which is at its file-size
/// ceiling; the two share the screen but not a file, the same split
/// `analytics_charts.dart` already uses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_section_header.dart';
import '../../widgets/success_flash.dart';

/// The screen-share resolution ceiling; index-matched to the segmented
/// options below. All lie inside the server's settable range (360 to 2160),
/// and 2160 is the default a deployment keeps until an admin sets one.
const _screenShareCapOptions = <(String, int)>[
  ('720p', 720),
  ('1080p', 1080),
  ('1440p', 1440),
  ('Source', 2160),
];

/// The screen-share resolution ceiling: client-advertised, so this is the
/// only enforcement there is - a client reads it and caps its own capture
/// parameters before starting a share, rather than the server inspecting
/// published tracks. Applies to every client, independent of the analytics
/// toggle above, so it stays visible and usable whether or not Space
/// analytics recording is on.
class ScreenShareCapSection extends ConsumerStatefulWidget {
  const ScreenShareCapSection({super.key});

  @override
  ConsumerState<ScreenShareCapSection> createState() =>
      _ScreenShareCapSectionState();
}

class _ScreenShareCapSectionState extends ConsumerState<ScreenShareCapSection>
    with GuardedActionState<ScreenShareCapSection> {
  bool _saving = false;
  int? _optimisticMaxHeight;

  Future<void> _setMaxHeight(int maxHeight) async {
    setState(() {
      _saving = true;
      _optimisticMaxHeight = maxHeight;
    });
    final ok = await guard(
      whatFailed: 'change the screen-share resolution ceiling',
      action: () =>
          ref.read(apiProvider).setSpaceScreenShareMaxHeight(maxHeight),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) _optimisticMaxHeight = null;
    });
    if (ok) ref.invalidate(spaceScreenShareCeilingProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final ceiling = ref.watch(spaceScreenShareCeilingProvider);
    ref.listen(spaceScreenShareCeilingProvider, (previous, next) {
      if (next.hasValue && !next.isLoading && _optimisticMaxHeight != null) {
        setState(() => _optimisticMaxHeight = null);
      }
    });
    final current = _optimisticMaxHeight ?? ceiling.valueOrNull ?? 2160;
    final selectedIndex = _screenShareCapOptions.indexWhere(
      (o) => o.$2 == current,
    );

    return SettingsSectionCard(
      title: 'Screen share quality',
      children: [
        Text(
          'The tallest resolution a screen share may publish at, applied to '
          'every client. Lower it to keep a share light on bandwidth and the '
          'media server; this is enforced by the sharing client, not checked '
          'on the server.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        AppSegmentedControl.inline(
          semanticLabel: 'Screen share resolution ceiling',
          options: [
            for (final option in _screenShareCapOptions)
              AppSegmentedOption(label: option.$1, disabled: _saving),
          ],
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onSegmentSelected: (i) => _setMaxHeight(_screenShareCapOptions[i].$2),
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
