// SPDX-License-Identifier: Apache-2.0
/// The caller's own notification preference: which messages are worth
/// waking a device for.
///
/// Unlike `presenceVisibilityDisplayProvider` (`presence_controller.dart`),
/// this needs no local-echo workaround: `GET /push/preference` is a genuine
/// round trip, not a per-viewer-derived answer, so the current value is
/// simply fetched.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

/// The caller's current preference, fetched fresh whenever watched.
/// `autoDispose` like [meProvider]: this is settings-screen state, nothing
/// else in the app needs it kept warm. A [api.NotFoundException] here means
/// the server predates the route, which the settings row reads as "not
/// offered by this server" rather than retrying a request that would only
/// 404 again; see `personal_status_sections.dart`'s `_NotificationPreferenceRow`.
final notificationPreferenceProvider =
    FutureProvider.autoDispose<api.NotificationPreference>(
      (ref) => ref.watch(apiProvider).notificationPreference(),
    );
