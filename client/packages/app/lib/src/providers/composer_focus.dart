// SPDX-License-Identifier: Apache-2.0
/// The one composer on screen registers its own focus node here, so the
/// global [AppAction.focusComposer] shortcut has something to reach: the
/// shell that binds the shortcut is not the composer's parent and has no
/// other handle on it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The mounted [Composer]'s own focus node, or null while none is on screen
/// (no channel selected, or a voice channel with no text composer at all).
final composerFocusNodeProvider = StateProvider<FocusNode?>((ref) => null);
