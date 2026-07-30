// SPDX-License-Identifier: Apache-2.0
/// The one place a drawn stroke becomes rows on the server.
///
/// Serial by design: one request in flight, FIFO. Ordering is what `z_index`
/// is seeded from, so two strokes committed concurrently could land in either
/// order and re-layer overlapping ink differently for every viewer.
library;

import 'dart:async';

import 'package:slimm_api/api.dart' as api;

/// What a commit did.
enum CommitOutcome { placed, failed }

/// One queued placement.
class CanvasCommit {
  CanvasCommit({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.props,
  });

  final String id;
  final double x;
  final double y;
  final double w;
  final double h;
  final Map<String, dynamic> props;
}

/// Sends placements one at a time, retrying only what a retry can fix.
class CanvasCommitQueue {
  CanvasCommitQueue({
    required this.client,
    required this.channelId,
    required this.onPlaced,
    required this.onFailed,
  });

  final api.SlimmApi client;
  final String channelId;
  final void Function(api.CanvasObject object) onPlaced;

  /// Called with the id and a sentence to show, once a commit is beyond retry.
  final void Function(String id, String message) onFailed;

  final List<CanvasCommit> _pending = <CanvasCommit>[];
  bool _running = false;
  bool _closed = false;

  void add(CanvasCommit commit) {
    if (_closed) return;
    _pending.add(commit);
    unawaited(_drain());
  }

  void close() => _closed = true;

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty && !_closed) {
        final commit = _pending.removeAt(0);
        await _send(commit);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _send(CanvasCommit commit) async {
    // Three tries backing off: a 429 while somebody scribbles must not lose ink already on their own screen.
    var delay = const Duration(milliseconds: 250);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final object = await client.placeCanvasObject(
          channelId,
          id: commit.id,
          kind: 'stroke',
          x: commit.x,
          y: commit.y,
          w: commit.w,
          h: commit.h,
          props: commit.props,
        );
        if (!_closed) onPlaced(object);
        return;
      } on api.ApiException catch (error) {
        if (_closed) return;
        if (!_retryable(error) || attempt == 2) {
          onFailed(commit.id, _explain(error));
          return;
        }
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  static bool _retryable(api.ApiException error) =>
      error is api.RateLimitedException ||
      error is api.UnavailableException ||
      error is api.TransportException;

  static String _explain(api.ApiException error) => switch (error) {
    api.ForbiddenException() => 'You cannot draw on this canvas right now.',
    api.ConflictException() => 'This canvas is full, or that id is taken.',
    api.BadRequestException() => 'That stroke was refused as too large.',
    _ => 'That stroke could not be saved.',
  };
}
