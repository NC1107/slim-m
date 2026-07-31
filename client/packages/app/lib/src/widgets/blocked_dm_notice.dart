// SPDX-License-Identifier: Apache-2.0
/// What a DM with a blocked person shows in place of its composer.
///
/// The channel itself is frozen server-side for exactly this pair
/// (`store/dms.rs` denies SEND, ADD_REACTIONS and ATTACH_FILES both
/// directions), so a composer here would only ever fail on send; this says
/// why instead of leaving a live-looking field that cannot work.
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_design_system/design_system.dart';

class BlockedDmNotice extends StatelessWidget {
  const BlockedDmNotice({required this.name, super.key});

  /// The blocked participant's display name.
  final String name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.s16),
    child: AppCallout(
      tone: AppCalloutTone.warn,
      child: Text(
        'You have blocked $name. Nothing sent here would reach them, so '
        'there is no composer to send from. Unblock them from settings to '
        'talk again.',
      ),
    ),
  );
}
