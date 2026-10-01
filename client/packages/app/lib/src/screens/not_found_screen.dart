// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What an address that matches no route shows, in the app's own voice rather
/// than the router's exception text.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/routes.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.info, size: 26, color: tokens.textSecondary),
                const SizedBox(height: AppSpacing.s12),
                Text(
                  'This page does not exist.',
                  textAlign: TextAlign.center,
                  style: AppText.title.copyWith(color: tokens.textPrimary),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'The link may be mistyped, or the page may have moved.',
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: tokens.textSecondary),
                ),
                const SizedBox(height: AppSpacing.s20),
                AppButton(
                  label: 'Back to channels',
                  variant: AppButtonVariant.primary,
                  onPressed: () => context.go(Routes.channels),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
