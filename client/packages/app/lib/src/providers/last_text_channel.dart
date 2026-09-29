// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The last non-voice conversation the shell showed, so hanging up a phone
/// call has somewhere to land that is not the voice channel's own screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Null until a text channel or DM has been shown this session.
final lastTextChannelProvider = StateProvider<String?>((ref) => null);
