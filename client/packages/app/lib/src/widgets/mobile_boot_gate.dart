// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Covers the very first server connection on a phone with a boot splash, so a
/// cold launch never lands on an empty, disconnected home while the session's
/// first catch-up is still running.
///
/// Desktop is left untouched: it already shows its own pre-`runApp` startup
/// screen (decision 0012) and its window is sized before the first frame, so
/// this gate returns the child unchanged on a desktop host.
///
/// The splash clears the moment the first catch-up lands
/// ([initialSyncCompleteProvider], which stays true for the rest of the
/// session) - so a later reconnect shows the rail's connection banner, never
/// this. If that first attempt fails instead, the splash steps aside for
/// whatever the local store already holds and its "Offline, retrying" banner,
/// rather than trapping a phone with no signal on a splash that never clears.
/// The `_sawConnecting` latch is what tells a real failure from the harmless
/// `offline` the controller rests in for an instant before its first connect.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart' show isDesktopHost;

import '../providers/sync_controller.dart';

/// Whether the boot splash should cover the home right now. Pure so its truth
/// table is tested directly, without a real mobile host or a live socket.
///
/// - Desktop is never gated: it has its own startup screen.
/// - Once the first catch-up lands ([synced]) the home shows for good.
/// - Before that, the splash holds through the resting `offline` and the
///   `connecting` attempt, and only steps aside once a seen attempt has
///   actually failed back to `offline` - so a phone with no signal reaches its
///   cached home rather than a splash that never clears.
@visibleForTesting
bool shouldShowBootSplash({
  required bool isMobile,
  required bool synced,
  required bool sawConnecting,
  required SyncStatus status,
}) {
  if (!isMobile || synced) return false;
  final firstAttemptFailed = sawConnecting && status == SyncStatus.offline;
  return !firstAttemptFailed;
}

class MobileBootGate extends ConsumerStatefulWidget {
  const MobileBootGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MobileBootGate> createState() => _MobileBootGateState();
}

class _MobileBootGateState extends ConsumerState<MobileBootGate> {
  /// Set once the first connect attempt is seen leaving the resting `offline`
  /// state. A plain field, not [setState]: [syncControllerProvider] is watched
  /// below, so the rebuild that would carry a status change already happens -
  /// this only latches what that rebuild saw.
  bool _sawConnecting = false;

  @override
  Widget build(BuildContext context) {
    if (isDesktopHost) return widget.child;

    final synced = ref.watch(initialSyncCompleteProvider);
    final status = ref.watch(syncControllerProvider);
    if (status == SyncStatus.connecting) _sawConnecting = true;

    final showSplash = shouldShowBootSplash(
      isMobile: true,
      synced: synced,
      sawConnecting: _sawConnecting,
      status: status,
    );
    return showSplash ? const BootSplashScreen() : widget.child;
  }
}

/// The phone's boot splash: the brand mark on the themed ground, with a quiet
/// spinner beneath so a slow first connect reads as working rather than stuck.
class BootSplashScreen extends StatelessWidget {
  const BootSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFadeIn(
              offset: 0,
              child: AppBrandMark(size: 56, color: tokens.accent),
            ),
            const SizedBox(height: AppSpacing.s32),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
