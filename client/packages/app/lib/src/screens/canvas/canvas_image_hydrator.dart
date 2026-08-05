// SPDX-License-Identifier: Apache-2.0
/// Fetches and decodes the bitmap for a placed image object arriving from
/// anywhere other than this client's own paste: the initial viewport fetch,
/// catch-up ops, and a live event from another participant.
///
/// [CanvasImagePaste] hands its own just-decoded bitmap straight to
/// [CanvasDocument.setImageBitmap], so pasting an image is instant. Every
/// other arrival only ever carried an attachment id - `props.attachment` on
/// the wire - and nothing fetched the bytes back, which meant an image was
/// visible only to the client that pasted it, only for the life of that
/// pane. This is the fix: a plain-Dart hydrator, the same shape as
/// `CanvasSync` and `CanvasOpsController`, that `CanvasPane` calls
/// unconditionally on every real placement and lets decide for itself
/// whether there is anything to fetch.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:slimm_api/api.dart' as api;
import 'package:slimm_voice_canvas/voice_canvas.dart';

/// A crude bound on total decoded pixel bytes, not a byte-accurate cache.
///
/// The roadmap names a bounded LRU (96 MB iOS, 256 MB Linux) for exactly
/// this reason; this is deliberately not that. One platform-uniform figure,
/// well under even the tighter iOS one, bounds every platform the same way
/// rather than branching on `Platform.isIOS` for a first pass, at the cost
/// of evicting more eagerly than a desktop could actually afford.
const int defaultMaxDecodedImageBytes = 64 * 1024 * 1024;

/// Hydrates a placed [api.CanvasObject]'s bitmap, bounded and safe to call
/// repeatedly for the same id.
///
/// **Eviction is not visibility-aware.** Freeing memory picks the
/// least-recently-hydrated id regardless of whether it is on screen right
/// now, so an evicted image that is still in view goes blank until the next
/// pan or reconnect re-fetches its region - `CanvasPane` already cold-fetches
/// the padded viewport on every camera settle, so this self-heals on the
/// next pan rather than needing its own retry timer. A real
/// visibility-ranked LRU would need to hook the cull cycle to know which
/// slots are actually on screen each frame, which is more machinery than a
/// crude bound needs to earn its place.
///
/// **A failed fetch is not retried automatically.** A 403 or 404 is a
/// legitimate, stable answer - the object's channel access changed, or the
/// attachment was swept as an orphan - not a transient error worth hammering
/// the attachment store over. The one way to retry is the pane's own
/// reopen, which constructs a fresh hydrator with an empty failure set.
class CanvasImageHydrator {
  CanvasImageHydrator({
    required this.client,
    required this.document,
    this.maxDecodedBytes = defaultMaxDecodedImageBytes,
  });

  final api.SlimmApi client;
  final CanvasDocument document;
  final int maxDecodedBytes;

  final Set<String> _pending = <String>{};
  final Set<String> _hydrated = <String>{};
  final Set<String> _failed = <String>{};
  final Queue<String> _lru = Queue<String>();
  final Map<String, int> _bytesById = <String, int>{};
  int _decodedBytes = 0;
  bool _disposed = false;

  /// Requests [object]'s bitmap if it names an image this hydrator has not
  /// already hydrated, failed, or started fetching. A no-op for a stroke, an
  /// image with no attachment id, or one already known - idempotent by id,
  /// the same property every other canvas read already leans on, so calling
  /// this on every viewport page or catch-up op costs nothing once an image
  /// has actually landed.
  void hydrate(api.CanvasObject object) {
    if (_disposed || object.kind != 'image') return;
    final attachmentId = object.props['attachment'];
    if (attachmentId is! String) return;
    final id = object.id;
    if (_pending.contains(id) ||
        _hydrated.contains(id) ||
        _failed.contains(id)) {
      return;
    }
    _pending.add(id);
    unawaited(_fetch(id, attachmentId));
  }

  Future<void> _fetch(String id, String attachmentId) async {
    try {
      final fetched = await client.fetchAttachment(attachmentId);
      final codec = await ui.instantiateImageCodec(fetched.bytes);
      final frame = await codec.getNextFrame();
      _pending.remove(id);
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _hydrated.add(id);
      _remember(id, frame.image);
      document.setImageBitmap(id, frame.image);
    } catch (_) {
      _pending.remove(id);
      // A 403 or a 404 is a real answer, not a bug, so nothing retries it.
      if (!_disposed) {
        _failed.add(id);
        document.markImageLoadFailed(id);
      }
    }
  }

  void _remember(String id, ui.Image image) {
    final bytes = image.width * image.height * 4;
    _bytesById[id] = bytes;
    _decodedBytes += bytes;
    _lru.add(id);
    while (_decodedBytes > maxDecodedBytes && _lru.length > 1) {
      final evictId = _lru.removeFirst();
      _hydrated.remove(evictId);
      _decodedBytes -= _bytesById.remove(evictId) ?? 0;
      document.evictImageBitmap(evictId);
    }
  }

  /// Marks every in-flight fetch's eventual answer as one to discard rather
  /// than apply to [document], which may itself be disposed by the time a
  /// pending [_fetch] completes.
  void dispose() => _disposed = true;
}
