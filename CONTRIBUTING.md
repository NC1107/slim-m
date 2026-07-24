# Contributing to slim-m

Thanks for helping build a lightweight, self-hostable messenger.

## Provenance: DCO, not a CLA

Every commit must be signed off under the [Developer Certificate of Origin](https://developercertificate.org/):

```
git commit -s
```

This adds a `Signed-off-by` line certifying you wrote or have the right to submit the change.
There is no CLA.

## Commits and releases

Pull request titles follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `feat!:` for breaking).
The repository squash-merges, using the PR title as the commit message, and release-please turns those titles into versions and changelogs.
Server and client are versioned independently; a change to `schema/` bumps both.

## Componentization

- The server is a Rust workspace of crates with narrow public surfaces; the client is a Dart pub workspace of small packages.
- Keep files small (a soft 300-line review budget, generated code excluded).
- `cargo fmt` and `cargo clippy -- -D warnings` must pass; the client must pass `dart analyze`.
- No emoji as interface chrome; use Lucide icons. CI enforces this.

## Running the server locally

```
cp .env.example .env
cargo run --bin slimm-server
curl localhost:8080/healthz
```

## Licensing

By contributing you agree your contribution is licensed under the license of the component you touch (see [LICENSING.md](LICENSING.md)): AGPL-3.0-only for the server, Apache-2.0 for the client and shared schema.
