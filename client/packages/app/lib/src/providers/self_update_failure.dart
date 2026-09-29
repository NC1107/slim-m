// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The last self-update failure, held until dismissed so it renders in the
/// persistent `AppErrorState` and never as a SnackBar.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop/self_update/self_update_failure.dart';

final selfUpdateFailureProvider = StateProvider<SelfUpdateFailure?>(
  (ref) => null,
);
