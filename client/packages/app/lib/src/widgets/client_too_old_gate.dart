// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one screen in this app that stops a working session: the server this
/// client is signed in to will not serve this build any more (decision
/// 0025).
///
/// Fail-open by construction. Only a floor that was actually read, and
/// actually higher than this build, blocks anything; a pending request, an
/// unreachable server, a version that will not parse and a server too old to
/// declare a floor at all every render the app untouched. Refusing to run
/// because a check did not answer would turn a flaky network into an
/// unusable app, which is worse than the problem the floor exists for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:url_launcher/url_launcher.dart';

import '../desktop/rpm_updater.dart';
import '../desktop/startup_screen.dart' show updateActionHint;
import '../providers/client_floor.dart';
import '../providers/providers.dart';

/// Where a build that cannot self-update sends someone instead.
const releasesUrl = 'https://github.com/NC1107/slim-m/releases';

/// Renders [child] unless this client is below the server's floor.
class ClientTooOldGate extends ConsumerWidget {
  const ClientTooOldGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floor = ref.watch(clientFloorProvider).valueOrNull;
    if (floor != ClientFloor.tooOld) return child;
    return const ClientTooOldScreen();
  }
}

class ClientTooOldScreen extends ConsumerStatefulWidget {
  const ClientTooOldScreen({super.key, this.format, this.rpm});

  /// Injectable for tests; the real build reads its own install format.
  final InstallFormat? format;
  final RpmUpdater? rpm;

  @override
  ConsumerState<ClientTooOldScreen> createState() => _ClientTooOldScreenState();
}

class _ClientTooOldScreenState extends ConsumerState<ClientTooOldScreen> {
  bool _busy = false;
  String? _error;
  bool _installed = false;

  InstallFormat get _format => widget.format ?? currentInstallFormat();

  /// dnf can finish the job from here, which is the whole point of asking on
  /// this screen rather than only telling: an rpm user is one prompt away
  /// from a client that works again.
  Future<void> _update() async {
    if (_format != InstallFormat.rpm) {
      final uri = Uri.tryParse(releasesUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await (widget.rpm ?? const RpmUpdater()).apply();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _installed = result.ok;
      _error = result.ok ? null : result.detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final mine = ref.watch(appInfoProvider).valueOrNull?.version;

    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  AppIcons.download,
                  size: AppSizes.icon32,
                  color: tokens.accent,
                ),
                const SizedBox(height: AppSpacing.s16),
                Text(
                  'This version can no longer connect',
                  textAlign: TextAlign.center,
                  style: AppText.heading.copyWith(color: tokens.textPrimary),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  mine == null
                      ? 'This Space has moved on to a newer version of '
                            'slim-m. Update to carry on.'
                      : 'This Space has moved on to a newer version of '
                            'slim-m. You are on $mine. Update to carry on.',
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: tokens.textSecondary),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  _installed
                      ? 'Installed. Restart slim-m to finish.'
                      : updateActionHint(_format),
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
                if (_error case final detail?) ...[
                  const SizedBox(height: AppSpacing.s16),
                  AppErrorState(
                    message: detail,
                    onDismiss: () => setState(() => _error = null),
                  ),
                ],
                const SizedBox(height: AppSpacing.s24),
                AppButton(
                  label: _format == InstallFormat.rpm
                      ? 'Update now'
                      : 'Open the release',
                  variant: AppButtonVariant.primary,
                  size: AppButtonSize.lg,
                  full: true,
                  busy: _busy,
                  disabled: _installed,
                  onPressed: _update,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
