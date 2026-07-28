// SPDX-License-Identifier: Apache-2.0
/// A live share is easy to forget about once the button that started it has
/// scrolled out of view; this says so plainly, wherever the call view is.
///
/// Its own file because `voice_screen.dart` was over this repo's line
/// budget already, the same reason `voice_call_controls.dart` split out.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Deliberately keyed to `VoiceState.screenSharing` alone:
/// `VoiceState.awaitingBroadcast` is a request nobody can see yet, and
/// showing this banner for it would be the exact lie that field exists to
/// stop.
class LocalScreenShareBanner extends StatelessWidget {
  const LocalScreenShareBanner({super.key});

  @override
  Widget build(BuildContext context) => const AppCallout(
    tone: AppCalloutTone.accent,
    icon: AppIcons.screenShare,
    child: Text('You are sharing your screen.'),
  );
}
