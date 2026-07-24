# Licensing

slim-m is multi-licensed by component, so the network-copyleft protection sits where it matters and the client stays permissive.

| Component | Path | License | SPDX |
|---|---|---|---|
| Home server | `crates/`, `docker/` | GNU AGPL v3.0 only | `AGPL-3.0-only` |
| Flutter client | `client/` | Apache License 2.0 | `Apache-2.0` |
| Shared wire schema | `schema/` | Apache License 2.0 | `Apache-2.0` |
| Push relay | separate repository | Apache License 2.0 | `Apache-2.0` |

Rationale: the official-hosted-plus-self-hosting model creates a real SaaS-rehosting risk that only AGPL's network clause closes, so the server is AGPL.
The client has no rehosting risk, AGPL on app-store binaries has caused real friction, and the client compiles in the Apache-2.0 generated schema code, so the client and the shared schema are Apache-2.0.
See [docs/STRATEGY.md](docs/STRATEGY.md) and [docs/research/oss.md](docs/research/oss.md).

Every source file carries an `SPDX-License-Identifier` header, and CI checks the server headers are present.

The canonical full license texts live in `LICENSES/AGPL-3.0-only.txt` and `LICENSES/Apache-2.0.txt` (REUSE style).
These verbatim texts are added as a mechanical step (for example `reuse download --all`) and are tracked as a Phase 0 checklist item; the per-component licensing above is authoritative in the meantime.
