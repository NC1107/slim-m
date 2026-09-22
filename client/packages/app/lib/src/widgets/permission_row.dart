// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// One permission and the control that sets it, shared by the two screens that
/// set permissions on something.
///
/// The role editor sets a bit on or off; the channel overwrite screen sets it
/// to allow, inherit or deny. That difference is real and has to survive - an
/// overwrite genuinely has three states. Everything around it did not have to
/// differ, and did: two separate widgets, two paddings, two label treatments,
/// so somebody who learned one screen did not recognise the other even though
/// both are "set permissions on a thing". This is the shared half.
///
/// [controlBelow] is the one thing still allowed to differ, and it is a
/// property of the control rather than of the viewport: a toggle fits beside
/// its label at any width this ships at, a three-segment allow/inherit/deny
/// control does not. Nothing here moves with width, which is what
/// `docs/design/desktop-vs-mobile.md` asks of a token-level decision - only
/// heights, hit targets and input font size are width levers, and this is none
/// of the three.
///
/// The permission list itself, and the wording of each entry, live in
/// `permissions.dart` as `Perm.editable`; both screens already read from there,
/// which is what keeps them from drifting apart again.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class PermissionRow extends StatelessWidget {
  const PermissionRow({
    super.key,
    required this.label,
    required this.control,
    this.controlBelow = false,
    this.dimmed = false,
  });

  /// The permission's name, as `Perm.editable` words it.
  final String label;

  /// The control that sets this permission: a toggle, or a segmented
  /// allow/inherit/deny. It carries its own semantic label, since only it
  /// knows what its values mean.
  final Widget control;

  /// Whether [control] sits under the label rather than beside it; see the
  /// library doc.
  final bool controlBelow;

  /// Whether this permission cannot be changed by the caller, which dims the
  /// label. The control still decides for itself what it does when tapped -
  /// dimming a label is a statement about the row, not a guard.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final text = Text(
      label,
      style: AppText.ui.copyWith(
        color: dimmed ? tokens.textSecondary : tokens.textPrimary,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: controlBelow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: AppSpacing.s4),
                control,
              ],
            )
          : Row(
              children: [
                Expanded(child: text),
                control,
              ],
            ),
    );
  }
}
