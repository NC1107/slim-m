# slim-m server performance baselines

This directory is the Phase 0 performance measurement scaffolding for
`crates/slimm-server`.
It does not enforce a regression gate yet.
It exists so that every release leaves behind one comparable, versioned
record of how fast the hot paths were at that point in time.

## The one-JSON-baseline-per-release model

Each server release gets exactly one committed baseline file.
The file lives at `perf/baselines/<version>.json`, where `<version>` matches
the `slimm-server` release version (for example `perf/baselines/0.3.0.json`).
There is no rolling "latest" file and no per-commit history.
A baseline is a snapshot taken at a release boundary, not a continuous trace.

`perf/baseline.example.json` in this directory is not a real baseline.
It is a template showing the required shape, so a new baseline file can be
produced by copying it and filling in real numbers.

Each baseline file has:

- a top-level `version` field, the `slimm-server` release version the
  numbers were captured against
- a `metrics` array, one entry per benchmark, each with:
  - `name`, the criterion benchmark name (for example `uuid_now_v7`)
  - `value`, the measured point estimate
  - `unit`, the unit the value is expressed in (for example `ns`)

Two entries are not criterion benchmarks: `idle_rss` and `peak_rss`, in kB.
They exist because the Phase 1 exit criterion is stated in terms of resident
memory rather than throughput, and a number nobody records is a number nobody
can hold a release to.
See "Measuring idle RSS" below for how to take them.

Keeping the shape flat and per-metric means a new baseline can be diffed
against the previous one metric by metric, without needing to parse
criterion's own (much larger) internal JSON format.

## Running the benchmarks locally

```sh
cargo bench -p slimm-server
```

This runs both Phase 0 benchmarks in `crates/slimm-server/benches/hot_paths.rs`
and writes a full HTML report plus raw JSON estimates to `target/criterion/`.
Open `target/criterion/report/index.html` to browse it.

To check that the benchmarks still compile without spending the time to
actually run them, use:

```sh
cargo bench -p slimm-server --no-run
```

## How CI uses this

`.github/workflows/perf.yml` treats compiling and running the benchmarks as
two separate, differently-priced steps:

- On every pull request touching `crates/**` or `perf/**`, CI only compiles
  the benches (`cargo bench --no-run`).
  This catches a benchmark that no longer builds without paying for a full
  measurement run on every push.
- On a published GitHub release, CI runs the benchmarks for real and
  uploads the `target/criterion` output as a workflow artifact.

Turning that uploaded criterion output into a new committed
`perf/baselines/<version>.json` is a manual step for now: pull the relevant
point estimates out of the artifact and add them to a new baseline file in
the same pull request that finalizes the release.
Automating that extraction is a later phase, not part of this scaffolding.

## Measuring idle RSS

STRATEGY.md budgets the server at under 30MB resident at true zero load, and
the Phase 1 exit criterion is that the figure has actually been measured.
Take it against a release build, not a debug one, with nothing connected:

```sh
cargo build --locked --release --bin slimm-server
SLIMM_PORT=8099 SLIMM_DATABASE_PATH=/tmp/rss-probe.db \
  ./target/release/slimm-server &
SRV=$!
sleep 5                              # let startup and migrations settle
curl -s localhost:8099/healthz       # confirm it is actually serving
grep -E '^VmRSS|^VmHWM' /proc/$SRV/status
kill $SRV
```

`VmRSS` is the steady idle figure the budget refers to.
`VmHWM` is the high-water mark, which peaks during migrations at startup and
then never recurs, so it is worth recording separately rather than mistaking it
for the idle cost.

The 0.8.0 baseline was taken this way on Fedora with glibc, measuring 7,296 kB
idle and 25,760 kB peak.
Note that releases ship a musl binary built in CI, and musl's allocator
fragments differently under Tokio, so a musl-built figure is the one that
finally settles the budget; this local glibc number is indicative and both
figures sit inside it with room to spare.

## Adding a new baseline

1. Let the release workflow run and download its `criterion-report` artifact.
2. Open the `estimates.json` file under each benchmark's directory (or read
   the numbers straight off the HTML report).
3. Copy `perf/baseline.example.json` to `perf/baselines/<version>.json`.
4. Fill in the `version` field and one `metrics` entry per benchmark.
5. Commit the new baseline file alongside the release.
