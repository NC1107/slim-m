# 0038 - A module is told an opaque caller id and nothing else

Status: accepted
Date: 2026-09-28

## The ask

Found by building a live poll as a module.
"One vote per person" cannot be written when the plain `run` request is only `{command, input}`.
The module cannot tell one person tapping twice from two people tapping once.

## What was unclear

[0023](0023-mediated-host-capabilities.md) describes a call context: module, space, invoking user, channel.
That context belongs to the deferred `host_call` path, not to `run`.
No record said so, and "a module knows nothing about who is asking" was an assumption rather than a written rule.

## Decision

The request a module receives gains one additive field: `caller: { "id": "<hex>" }`.

- The id is `sha256("slim-module-caller-v1" NUL module_id NUL user_id)` in lowercase hex.
  It is stable per person per module, so a module can dedupe against itself.
  It differs between modules, so two modules cannot be joined up to follow one person.
  It is not the user id, and the user id is not recoverable from it in practice.
- Nothing else is added: no display name, no channel, no space, no roles, no permissions.
  A module only runs when the caller holds its permission, so that answer is always yes and carries no information.
- No manifest capability gates it.
  A capability exists to bound power, and an opaque id grants none: it cannot act, read or spend anything.
  Gating it would make every module declare something to receive a value that grants nothing.
- The ABI stays v1.
  The field is additive, a module that ignores it keeps working, and modules are told to ignore unknown fields.

## What this deliberately does not do

- A module still cannot act as the caller.
  That stays [0023](0023-mediated-host-capabilities.md) Phase D territory, behind review, rate limits and permission checks.
- The channel is not sent.
  The generic run route has no channel, and a channel would be a second identifier a module could correlate with.
  If a real module needs it, that is a new record.
- Per-viewer scene state stays unsupported.
  A scene `state` is the same for every viewer, so hidden-information games are out of scope.
  `kv.store`, once enforced, is the place for a module's own secrets.

## Consequences

- The id is unkeyed, so someone who already knows a user id and a module id can compute it.
  That reveals nothing they did not already have, and a per-deployment key would change every id on a secret rotation.
- Deleting and recreating an account gives a new user id and so a new caller id.
- Existing modules are unaffected.
