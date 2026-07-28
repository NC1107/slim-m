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

Four entries are not criterion benchmarks: `idle_rss_glibc`, `peak_rss_glibc`,
`idle_rss_musl` and `peak_rss_musl`, all in kB.
They exist because the Phase 1 exit criterion is stated in terms of resident
memory rather than throughput, and a number nobody records is a number nobody
can hold a release to.
The libc is part of the metric name, not a side note, because glibc and musl
genuinely measure different things here (musl's allocator fragments
differently under Tokio) and a bare `idle_rss` name has already caused one
baseline (0.8.0) to record a glibc number with no way to tell that from the
name alone.
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
Take it against a release build, not a debug one, with nothing connected, on
both libcs: the host's glibc, and the musl build every release actually ships
(built the same way CI builds it, from the committed
`docker/server.Dockerfile`, so it needs Docker but not a musl toolchain
locally).

`perf/measure-idle-rss.sh` automates both, after you build the glibc binary:

```sh
cargo build --locked --release --bin slimm-server
perf/measure-idle-rss.sh
```

It starts each build with nothing connected, confirms it over `/healthz`,
reads `VmRSS` (the steady idle figure the budget refers to) and `VmHWM` (the
high-water mark, which peaks during startup migrations and never recurs, so
it is worth recording separately rather than mistaking it for the idle cost)
out of `/proc/<pid>/status`, then tears the process or container down.
Run it with `--skip-musl` if Docker is not available, or `--skip-glibc` /
`--skip-musl` to isolate one side while debugging the other; the full flag
list is in its own header comment.

Take several readings rather than trusting a single run.
RSS is noisy enough (page-cache timing, what else the host is doing) that one
sample can read 2-3% high or low; the 0.15.0 baseline below is the median of
five runs of the script, and each individual run printed within about 2% of
that median on this machine.

The 0.8.0 baseline was taken this way on Fedora with glibc only, measuring
7,296 kB idle and 25,760 kB peak, and flagged that releases ship musl instead
without being able to measure it.
0.15.0 is the first baseline with both figures: see
`perf/baselines/0.15.0.json` and the release notes for the comparison, and do
not compare a `_glibc` figure against a `_musl` one, or either against the
unqualified `idle_rss`/`peak_rss` names 0.8.0 used before this split existed.

**This is deliberately not wired into CI.**
The criterion benchmarks above are fine to run on a shared GitHub Actions
runner because they measure relative cost, not an absolute budget.
RSS is the opposite: the whole reason 0.8.0's number carries a glibc-versus-musl
caveat is that the exact host matters, and a virtualized CI runner is a third
environment, not a stand-in for either the release binary's real deployment
target or a contributor's own machine.
A number captured there would look exactly as authoritative as this one while
measuring something different, which is a worse failure mode than the manual
step it would replace.
Take this measurement by hand, on real hardware, at each release.

## Adding a new baseline

1. Let the release workflow run and download its `criterion-report` artifact.
2. Open the `estimates.json` file under each benchmark's directory (or read
   the numbers straight off the HTML report).
3. Separately, on real hardware, build the release binary and run
   `perf/measure-idle-rss.sh` (see "Measuring idle RSS" above).
4. Copy `perf/baseline.example.json` to `perf/baselines/<version>.json`.
5. Fill in the `version` field, one `metrics` entry per criterion benchmark,
   and the four RSS entries the script printed.
6. Commit the new baseline file alongside the release.
