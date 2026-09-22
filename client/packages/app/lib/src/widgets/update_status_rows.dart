// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What Settings > About says about updates: whether one is waiting, and a
/// way to ask again without relaunching.
///
/// Both numbers, deliberately. The owner's complaint that led to decision
/// 0025 was that a prompt naming one version could not be triaged from a
/// screenshot - "0.79.0 is available" says nothing about whether the person
/// reporting it is one release behind or nine. "0.79.0 is available. You have
/// 0.78.0." answers that in the same glance.
///
/// The manual check runs the same [checkForClientUpdate] the splash and the
/// six-hourly watcher run, and writes the same [inSessionUpdateProvider], so
/// there is one place a find lives and no second polling path. It differs from
/// the watcher in one way on purpose: it ignores the dismissal the banner
/// records. Somebody who presses "Check for updates" is asking, and answering
/// "you are up to date" because they waved the banner away earlier would be a
/// lie.
///
/// Absent entirely where the check cannot run - iOS has TestFlight, a store
/// build updates itself, and `SLIMM_NO_UPDATE_CHECK` switches the whole thing
/// off - because a control that can never find anything is worse than no
/// control. That is the same [updateWatchShouldRun] the watcher gates on.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../desktop/startup_screen.dart';
import '../desktop/update_check.dart';
import '../desktop/update_watch.dart';
import '../providers/providers.dart';

class UpdateStatusRows extends ConsumerStatefulWidget {
  const UpdateStatusRows({
    super.key,
    this.check = checkForClientUpdate,
    this.shouldRun = updateWatchShouldRun,
  });

  /// Injected the way [UpdateWatcher] takes its own: the real one reaches the
  /// network, which a widget test must not.
  final CheckForClientUpdate check;

  /// Whether this build ever checks at all; see the library doc.
  final bool Function() shouldRun;

  @override
  ConsumerState<UpdateStatusRows> createState() => _UpdateStatusRowsState();
}

class _UpdateStatusRowsState extends ConsumerState<UpdateStatusRows> {
  bool _checking = false;

  /// What the last manual check found, shown until the next one. Null before
  /// any check, and cleared while one is running so a stale answer cannot sit
  /// under a spinner.
  String? _result;

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    try {
      final info = await ref.read(appInfoProvider.future);
      final update = await widget.check(currentVersion: info.version);
      if (!mounted) return;
      if (update != null) {
        ref.read(inSessionUpdateProvider.notifier).state = update;
      }
      setState(() {
        _result = update == null
            ? 'You are on the latest version.'
            : 'Version ${update.version} is available.';
      });
    } catch (_) {
      // Best-effort, like every path in decision 0025: no error surfaced.
      if (mounted) setState(() => _result = 'Could not check just now.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.shouldRun()) return const SizedBox.shrink();
    final update = ref.watch(inSessionUpdateProvider);
    final installed = ref.watch(appInfoProvider).valueOrNull?.version;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (update != null && installed != null)
          AppListRow(
            leading: const Icon(AppIcons.download),
            label: '${update.version} is available. You have $installed.',
            subtitle: updateActionHint(update.format),
          ),
        AppListRow(
          leading: const Icon(AppIcons.retry),
          label: 'Check for updates',
          subtitle: _result,
          meta: _checking ? 'Checking…' : null,
          onTap: _checking ? null : () => unawaited(_checkNow()),
        ),
      ],
    );
  }
}
