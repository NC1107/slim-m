// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The no-source answer, used where `dart:io` does not exist (web).
library;

import 'now_playing.dart';

NowPlayingSource? createNowPlayingSource({bool? linux, bool? windows}) => null;
