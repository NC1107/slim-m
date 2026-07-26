// SPDX-License-Identifier: Apache-2.0
/// A keycap: the visual stand-in for a key, or short label, used to show a
/// keyboard shortcut.
///
/// A hairline-bordered mono chip, never filled. A shortcut such as
/// "Ctrl+K" is composed by placing more than one [AppKbd] side by side (with
/// a plain separator between them, drawn by the caller): this widget only
/// draws one keycap, matching the source design, which does not model a
/// multi-key chain internally either.
library;

import 'package:flutter/material.dart';

import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';

class AppKbd extends StatelessWidget {
  const AppKbd(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        label,
        style: AppText.micro
            .copyWith(fontFamily: AppFonts.mono, color: tokens.textSecondary),
      ),
    );
  }
}
