# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Thin wrappers over the canvas HTTP surface, one function per verb.

Every write retries past a 429 the same way every other seed script's
writes do (`seed_backoff.call_with_backoff`); `Class::Canvas`'s budget (60
burst, 10/s refill - crates/slimm-server/src/ratelimit.rs) is generous
enough that a normal-sized seeding run rarely needs it, but a burst of
history ops right after a large placement pass can still outrun it.
"""
import urllib.parse

import seed_backoff


def place_object(api, channel_id, placement):
    return seed_backoff.call_with_backoff(
        lambda: api.call("POST", f"/channels/{channel_id}/canvas/objects",
                          placement))


def submit_op(api, channel_id, op):
    return seed_backoff.call_with_backoff(
        lambda: api.call("POST", f"/channels/{channel_id}/canvas/ops", op))


def remove(api, channel_id, op_id, object_ids):
    return submit_op(api, channel_id,
                      {"id": op_id, "kind": "remove", "object_ids": object_ids})


def clear(api, channel_id, op_id, before_seq):
    return submit_op(api, channel_id,
                      {"id": op_id, "kind": "clear", "before_seq": before_seq})


def restore(api, channel_id, op_id, target_op):
    return submit_op(api, channel_id,
                      {"id": op_id, "kind": "restore", "target_op": target_op})


def move(api, channel_id, op_id, object_id, x, y, w, h):
    return submit_op(api, channel_id,
                      {"id": op_id, "kind": "move", "object_id": object_id,
                       "x": x, "y": y, "w": w, "h": h})


def reorder(api, channel_id, op_id, object_id, z_index):
    return submit_op(api, channel_id,
                      {"id": op_id, "kind": "reorder", "object_id": object_id,
                       "z_index": z_index})


def viewport(api, channel_id, rect, limit=None):
    params = {"min_x": rect[0], "min_y": rect[1], "max_x": rect[2],
              "max_y": rect[3]}
    if limit is not None:
        params["limit"] = limit
    query = urllib.parse.urlencode(params)
    return seed_backoff.call_with_backoff(
        lambda: api.call("GET", f"/channels/{channel_id}/canvas/objects?{query}"))


def ops_page(api, channel_id, after_seq, limit=None):
    params = {"after_seq": after_seq}
    if limit is not None:
        params["limit"] = limit
    query = urllib.parse.urlencode(params)
    return seed_backoff.call_with_backoff(
        lambda: api.call("GET", f"/channels/{channel_id}/canvas/ops?{query}"))


def upload_attachment(api, filename, data, content_type):
    quoted = urllib.parse.quote(filename)
    return seed_backoff.call_with_backoff(
        lambda: api.call("POST", f"/attachments?filename={quoted}",
                          raw=data, content_type=content_type))
