// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The no-source answer, used where `dart:io` does not exist (web).
library;

import 'game_source.dart';

GameSource? createGameSource({bool? linux, bool? windows, bool? macos}) => null;
