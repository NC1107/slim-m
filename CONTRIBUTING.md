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

By contributing you agree that your contribution is licensed under [PolyForm Noncommercial 1.0.0](LICENSE) (see [LICENSING.md](LICENSING.md)), and that you additionally grant NC1107 a perpetual, worldwide, irrevocable, royalty-free license to use, modify and relicense your contribution under any terms, including commercial ones. That second part is what keeps commercial licensing possible without having to track every contributor down later.
