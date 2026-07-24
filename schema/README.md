# Wire protocol schema

`openapi.yaml` is the single source of record for the slim-m client-server wire protocol.

The Rust server types and the Dart client types are both generated from this file.
CI regenerates both and fails on any diff, so the schema and the code cannot drift.
The schema evolves additive-only; an oasdiff breaking-change gate blocks incompatible changes.

The server-to-relay push envelope is a separate versioned contract that lives in the relay repository.

This directory is Apache-2.0 licensed so the generated client code stays permissive.

Phase 0 defines only the liveness and version endpoints.
The messaging, auth, RBAC, sync, and WebSocket-envelope definitions are added in Phase 1.
