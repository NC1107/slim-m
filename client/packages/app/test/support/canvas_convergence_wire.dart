// SPDX-License-Identifier: Apache-2.0
/// Wire encoding for `canvas_convergence_harness.dart`: turns a canonical
/// op (`canvas_convergence_model.dart`) into the JSON a catch-up page would
/// answer with, or the live `ServerEvent` a socket would deliver. Split out
/// of the harness once it neared the file budget.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:slimm_api/api.dart' as api;

import 'canvas_convergence_model.dart';

const String _author = 'author';

http.Response jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _wireObject(CanonPlace op) => {
  'id': op.id,
  'kind': 'stroke',
  'z_index': op.zIndex,
  'x': op.x,
  'y': op.y,
  'w': op.w,
  'h': op.h,
  'props': {
    'points': [0.0, 0.0, op.w, op.h],
  },
  'author_id': _author,
  'seq': op.seq,
  'created_at': 0,
};

/// The catch-up feed's own shape for one op, as `GET .../canvas/ops`
/// answers it.
Map<String, dynamic> wireOp(CanonOp op) => switch (op) {
  CanonPlace() => {
    'seq': op.seq,
    'id': 'place-${op.seq}',
    'actor_id': _author,
    'created_at': 0,
    'kind': 'place',
    'object': _wireObject(op),
  },
  CanonMove(
    :final opId,
    :final objectId,
    :final x,
    :final y,
    :final w,
    :final h,
  ) =>
    {
      'seq': op.seq,
      'id': opId,
      'actor_id': _author,
      'created_at': 0,
      'kind': 'move',
      'object_id': objectId,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
    },
  CanonRemove(:final opId, :final objectIds) => {
    'seq': op.seq,
    'id': opId,
    'actor_id': _author,
    'created_at': 0,
    'kind': 'remove',
    'object_ids': objectIds,
  },
  CanonClear(:final opId, :final beforeSeq) => {
    'seq': op.seq,
    'id': opId,
    'actor_id': _author,
    'created_at': 0,
    'kind': 'clear',
    'before_seq': beforeSeq,
  },
  CanonRestore(:final opId, :final targetOpId, :final objectIds) => {
    'seq': op.seq,
    'id': opId,
    'actor_id': _author,
    'created_at': 0,
    'kind': 'restore',
    'target_op': targetOpId,
    'object_ids': objectIds,
  },
};

/// The live socket frame one op would arrive as, as `dispatchCanvasLiveEvent`
/// switches on it.
api.ServerEvent eventFor(CanonOp op, String channelId) => switch (op) {
  CanonPlace() => api.CanvasObjectPlaced(
    channelId: channelId,
    object: api.CanvasObject.fromJson(_wireObject(op)),
  ),
  CanonMove(
    :final opId,
    :final objectId,
    :final x,
    :final y,
    :final w,
    :final h,
  ) =>
    api.CanvasObjectMoved(
      channelId: channelId,
      seq: op.seq,
      opId: opId,
      objectId: objectId,
      x: x,
      y: y,
      w: w,
      h: h,
    ),
  CanonRemove(:final opId, :final objectIds) => api.CanvasObjectsRemoved(
    channelId: channelId,
    seq: op.seq,
    opId: opId,
    objectIds: objectIds,
  ),
  CanonClear(:final opId, :final beforeSeq) => api.CanvasCleared(
    channelId: channelId,
    seq: op.seq,
    opId: opId,
    beforeSeq: beforeSeq,
  ),
  CanonRestore(:final opId, :final objectIds) => api.CanvasObjectsRestored(
    channelId: channelId,
    seq: op.seq,
    opId: opId,
    objectIds: objectIds,
  ),
};
