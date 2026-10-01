// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The persistent home for a self-update failure or rollback, mounted in
/// `DesktopChrome`; never a SnackBar (decision 0041).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:url_launcher/url_launcher.dart';

import 'self_update_controller.dart';

class SelfUpdateFailureBanner extends ConsumerWidget {
  const SelfUpdateFailureBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = ref.watch(selfUpdateFailureProvider);
    if (failure == null) return const SizedBox.shrink();
    final releaseUri = failure.releaseUrl == null
        ? null
        : Uri.tryParse(failure.releaseUrl!);
    return AppErrorState(
      message: failure.message,
      detail: failure.detail,
      retryLabel: 'Open release page',
      onRetry: releaseUri == null
          ? null
          : () => launchUrl(releaseUri, mode: LaunchMode.externalApplication),
      onDismiss: () =>
          ref.read(selfUpdateFailureProvider.notifier).state = null,
    );
  }
}
