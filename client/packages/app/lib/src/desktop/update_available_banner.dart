// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The visible half of `update_watch.dart`: a persistent, dismissible strip
/// saying a newer build is there, for someone who never quits long enough to
/// see the splash's own offer. Mounted in `DesktopChrome` beside
/// [FirstRunTrayNoticeBanner], the same "say it once, quietly, and let the
/// user dismiss it" shape that banner already uses instead of a `SnackBar`.
///
/// On a build that passes back through a splash, this says only that a
/// restart gets it and not how: `startup_updates` already knows the
/// format-specific mechanism (dnf, the release page, ...) and re-derives it
/// on restart, so repeating that branching here would only be a second place
/// for it to drift out of sync with the splash's own copy.
///
/// Android has no such splash and no store to hand off to, so telling
/// somebody there to restart would be advice that does nothing. It gets the
/// release page instead, which is the only thing that actually helps a
/// sideloaded install.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/providers.dart';
import 'update_check.dart';
import 'update_watch.dart';

class UpdateAvailableBanner extends ConsumerWidget {
  const UpdateAvailableBanner({super.key, this.restartApplies});

  /// Whether restarting is what gets the update on this build, overridable
  /// for tests the way [ClientTooOldGate] takes its own `format`: the real
  /// answer reads `Platform.isAndroid`, which a test host cannot fake.
  final bool? restartApplies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Forces UpdateWatcher into existence for as long as this stays mounted.
    ref.watch(updateWatcherProvider);
    if (!ref.watch(bannerVisibleProvider)) return const SizedBox.shrink();
    final update = ref.watch(inSessionUpdateProvider)!;

    // A sideloaded apk never re-runs the splash, so a restart gets it nothing.
    final restartApplies = this.restartApplies ?? !isAndroidHost;

    return AppCallout(
      tone: AppCalloutTone.info,
      child: Row(
        children: [
          Expanded(
            child: Text(
              restartApplies
                  ? 'Version ${update.version} is available. Restart slim-m '
                        'to update.'
                  : 'Version ${update.version} is available.',
            ),
          ),
          if (!restartApplies)
            AppButton(
              label: 'Get it',
              variant: AppButtonVariant.ghost,
              onPressed: () => unawaited(_openRelease(update)),
            ),
          AppIconButton(
            icon: AppIcons.dismiss,
            semanticLabel: 'Dismiss',
            size: AppIconButtonSize.sm,
            onPressed: () => _dismiss(ref, update),
          ),
        ],
      ),
    );
  }

  /// Opens the release page, where the apk is attached. Best-effort like
  /// every other step in this path: a device with nothing registered for the
  /// url does nothing rather than throwing into a banner.
  Future<void> _openRelease(ClientUpdate update) async {
    final uri = Uri.tryParse(update.releaseUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _dismiss(WidgetRef ref, ClientUpdate update) async {
    ref.read(dismissedBannerVersionProvider.notifier).state = update.version;
    final prefs = await ref.read(preferencesProvider.future);
    await prefs.setString(dismissedUpdateVersionKey, update.version);
  }
}
