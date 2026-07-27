// SPDX-License-Identifier: Apache-2.0
/// The other half of pinning a server's identity: a later connection whose
/// key does not match what was pinned before. Trust-on-first-use exists to
/// make exactly this visible, so nothing here may read like the routine
/// first-connect confirmation it is not.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import 'server_fingerprint_step.dart';

/// Shown when the address answers with a different key than the one already
/// pinned for it. Requires an explicit acknowledgement before the one action
/// that re-pins the new key even unlocks, so it cannot be tapped through the
/// way the ordinary confirmation can. Pops `true` only if that action fires;
/// `false` on cancel.
class ServerIdentityChangedStep extends StatefulWidget {
  const ServerIdentityChangedStep({
    super.key,
    required this.address,
    required this.identity,
  });

  final Uri address;
  final api.ServerIdentity identity;

  @override
  State<ServerIdentityChangedStep> createState() =>
      _ServerIdentityChangedStepState();
}

class _ServerIdentityChangedStepState extends State<ServerIdentityChangedStep> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'STEP 2 OF 3',
                  style: AppText.label.copyWith(color: tokens.textSecondary),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  "This server's identity changed",
                  style: AppText.heading.copyWith(
                    color: tokens.dangerText,
                    fontWeight: AppWeights.semi,
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  widget.address.toString(),
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
                const SizedBox(height: AppSpacing.s24),
                AppCallout(
                  tone: AppCalloutTone.warn,
                  child: Text(
                    'The key this server presents does not match the one '
                    'pinned the last time this app connected here. That can '
                    'be an honest change, a re-key or a move to new '
                    'hosting, or it can mean this connection no longer '
                    'reaches the server that was trusted before. Confirm '
                    'the code below with whoever runs it before trusting '
                    'it again.',
                  ),
                ),
                const SizedBox(height: AppSpacing.s24),
                FingerprintDisplay(identity: widget.identity),
                const SizedBox(height: AppSpacing.s24),
                CheckboxListTile(
                  value: _acknowledged,
                  onChanged: (v) => setState(() => _acknowledged = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'I have confirmed this new code with whoever runs this '
                    'server.',
                    style: AppText.caption.copyWith(color: tokens.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                AppButton(
                  label: 'Trust the new identity',
                  variant: AppButtonVariant.danger,
                  full: true,
                  disabled: !_acknowledged,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: AppSpacing.s12),
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.secondary,
                  full: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
