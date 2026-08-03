// SPDX-License-Identifier: Apache-2.0
/// Setting the deployment's channel order and category placement from the
/// rail: `PUT /channels/order` ([api.SlimmApiChannelAdmin.reorderChannels]).
///
/// Optimistic, the same shape `BlocksController.block` uses: the new
/// arrangement renders the instant a drag completes, and the round trip only
/// decides whether it sticks. The local store is never rewritten ahead of
/// the server's answer - `pendingOrder` is what the rail renders meanwhile,
/// because the server is what assigns the real position values, and every
/// other client with this rail open has to agree on the same ones.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../api_failure.dart';
import 'providers.dart';

/// What the rail should show while a reorder is in flight or has failed.
class ChannelOrderState {
  const ChannelOrderState({this.pendingOrder, this.error});

  /// The whole rail, grouped by category, this client asked for and has not
  /// yet heard confirmed or refused. Null once the request settles either
  /// way: on success the local store already holds the confirmed
  /// arrangement, and on failure the rail falls back to showing what it had
  /// before this attempt.
  final List<api.ChannelOrderGroup>? pendingOrder;

  /// What to show if the last attempt failed, or null.
  final String? error;
}

class ChannelOrderController extends StateNotifier<ChannelOrderState> {
  ChannelOrderController(this._ref) : super(const ChannelOrderState());

  final Ref _ref;
  List<api.ChannelOrderGroup>? _lastAttempt;

  /// Submits [groups] - the whole rail, grouped by category, in the
  /// arrangement a drag produced - and renders it immediately. A channel of
  /// any kind may be named in any group: a category decides placement only,
  /// never behaviour (docs/decisions/0006-channel-categories.md).
  Future<void> reorder(List<api.ChannelOrderGroup> groups) async {
    _lastAttempt = groups;
    state = ChannelOrderState(pendingOrder: groups);
    try {
      final updated = await _ref.read(apiProvider).reorderChannels(groups);
      final store = await _ref.read(storeProvider.future);
      await store.upsertChannels(updated);
      if (mounted) state = const ChannelOrderState();
    } on api.ApiException catch (e) {
      if (!mounted) return;
      state = ChannelOrderState(
        error: describeApiFailure('reorder channels', e),
      );
    }
  }

  /// Retries the arrangement that last failed, or does nothing if none did.
  Future<void> retry() {
    final attempt = _lastAttempt;
    return attempt == null ? Future<void>.value() : reorder(attempt);
  }

  /// Clears a failure without retrying, accepting the reverted arrangement.
  void dismiss() {
    if (mounted) state = const ChannelOrderState();
  }
}

final channelOrderControllerProvider =
    StateNotifierProvider<ChannelOrderController, ChannelOrderState>(
      (ref) => ChannelOrderController(ref),
    );
