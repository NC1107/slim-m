# slim-m

A lightweight, cross-platform, open source messaging platform with optional self-hosting.

`slim-m` is a working name; the final name is undecided.

## Status

Phase 0 (foundations) is underway.
The server skeleton compiles, runs, migrates its embedded SQLite database, and serves liveness and version endpoints; the surrounding build, CI, and release machinery is being stood up.
See the [roadmap](docs/ROADMAP.md) for phases and exit criteria.

## Layout

```
crates/slimm-server   Rust home server (Axum + embedded SQLite via sqlx)
schema/               OpenAPI (openapi.yaml), the single source of record for the wire protocol - hand-written types on both sides, not generated from it
client/               Flutter client (Dart pub workspace of small packages)
docker/               Production container image for the server
docs/                 Brief, strategy, roadmap, decisions, and research
```

The push relay is a separate repository, adapted from [check-in-relay](https://github.com/NC1107/check-in-relay).

## Running the server

```bash
cp .env.example .env
cargo run --bin slimm-server
curl localhost:8080/healthz     # -> ok
curl localhost:8080/version     # -> {"name":"slim-m",...}
```

## Documents

- API reference: [schema/openapi.yaml](schema/openapi.yaml) is the source of record; a rendered HTML copy is attached to each schema-ci run as the `api-docs` artifact, or build one locally with `npx @redocly/cli build-docs schema/openapi.yaml -o /tmp/api.html`
- [Brief](docs/BRIEF.md), [strategy](docs/STRATEGY.md), [roadmap](docs/ROADMAP.md)
- [Decisions of record](docs/decisions/), [backlog](docs/BACKLOG.md)
- [Licensing](LICENSING.md) (AGPL-3.0 server, Apache-2.0 client and schema), [contributing](CONTRIBUTING.md)

## License

Multi-licensed by component; see [LICENSING.md](LICENSING.md).
