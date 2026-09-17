# slim-m

A lightweight, cross-platform, open source messaging platform with optional self-hosting.

`slim-m` is a working name; the final name is undecided.

## Status

Phases 0 through 4 (foundations, server and protocol core, client shell, push notifications, voice and screen share) are complete, and later phases are substantially underway: a first Voice Canvas write slice, the admin and moderation screens, the client capability handshake, and part of the motion, accessibility and audio-design polish pass have all shipped.
Both components ship signed release artifacts and run on a live self-hosted instance; the `.release-please-manifest.*.json` files carry the current versions rather than this paragraph, which went stale by forty releases the last time it named them.
See [CLAUDE.md](CLAUDE.md) for what has shipped most recently and the [roadmap](docs/ROADMAP.md) for phases and exit criteria.

## Layout

```
crates/slimm-server   Rust home server (Axum + embedded SQLite via sqlx)
schema/               OpenAPI (openapi.yaml), the single source of record for the wire protocol - hand-written types on both sides, not generated from it
client/               Flutter client (Dart pub workspace of small packages)
docker/               Production container image for the server
docs/                 Brief, strategy, roadmap, decisions, and research
```

The push relay is a separate repository, adapted from [check-in-relay](https://github.com/NC1107/check-in-relay).

## Installing the app

If you are joining someone's space rather than running one, see **[docs/INSTALL.md](docs/INSTALL.md)** - one section per platform, including the security warnings Windows, macOS and Android will show you and what to click.
Ask whoever runs the space for its address and an invite code before you start.

If the space offers a web client, opening that address in a browser needs no install at all and is the easiest route.

## Self-hosting a server

The full walkthrough is [deploy/README.md](deploy/README.md).
Text chat needs one DNS record and two values in a `.env`; voice and screen share are an overlay you add when you want them.

## Running the server

```bash
cp .env.example .env
cargo run --bin slimm-server
curl localhost:8080/healthz     # -> ok
curl localhost:8080/version     # -> {"name":"slim-m",...}
```

## Documents

- API reference: [schema/openapi.yaml](schema/openapi.yaml) is the source of record; nothing renders it automatically (GitHub has no built-in OpenAPI viewer and building one into a CI artifact nobody downloads was not worth a job), so build a browsable copy locally with `npx @redocly/cli build-docs schema/openapi.yaml -o /tmp/api.html`
- [Brief](docs/BRIEF.md), [strategy](docs/STRATEGY.md), [roadmap](docs/ROADMAP.md)
- [Decisions of record](docs/decisions/), [backlog](docs/BACKLOG.md)
- [Licensing](LICENSING.md) (PolyForm Noncommercial, whole repo), [contributing](CONTRIBUTING.md)

## License

[PolyForm Noncommercial 1.0.0](LICENSE), one license for the whole repository; see [LICENSING.md](LICENSING.md).

Free for noncommercial use: personal, hobby, educational, research, nonprofit, and all that.
You can fork it, change it and redistribute it, you just can't sell it or use it commercially without asking first.
If you want to use it commercially, open an issue and ask.
