// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The last refused moderation write, held for the member pane to show.
///
/// Row menus and the profile popover close before their request answers, so
/// they have no place of their own for a failure. The pane outlives them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Null when nothing is wrong; cleared by the pane's dismiss control and at
/// the start of the next moderation write.
final memberModerationErrorProvider = StateProvider<String?>((ref) => null);
