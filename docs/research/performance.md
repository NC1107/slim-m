# Performance Engineering Program

Status: pre-implementation research, feeds into STRATEGY.md.
Scope: concrete performance budgets across client and server, the measurement and benchmark infrastructure to build starting Phase 0, CI regression gates, per-platform profiling workflow, and how the admin-facing "track performance over time" requirement gets satisfied.
This report treats performance as owned infrastructure, not a set of aspirational numbers, matching the brief's "optimize continuously" principle and the reference project's own `docs/voice-lounge/perf-baseline.md` precedent, already cited as a model in the backend report.

## 1. Client budgets

One table, revisited at every major release rather than left as folklore:

| Metric | Target |
|---|---|
| Cold start (Linux, Fedora) | under 1.2s to first interactive frame |
| Cold start (iOS, mid-tier device) | under 1.5s to first interactive frame |
| Warm start (both platforms) | under 500ms |
| Idle memory, foreground (iOS) | under 150MB resident |
| Idle memory, foreground (Linux) | under 200MB resident |
| Active voice call plus canvas, few bubbles (iOS) | under 250MB resident |
| Active voice call plus canvas (Linux) | under 400MB resident, includes the 256MB decoded-bitmap cache ceiling already set in the Voice Canvas report |
| App size, compressed (iOS) | under 60MB download |
| Binary size (Linux, AppImage) | under 80MB |
| Steady-state frame time | under 16.6ms (60fps), under 8.3ms on ProMotion (120fps) |
| Jank budget | fewer than 1% of frames exceed 2x the frame budget, measured over a rolling session |

Start-time and frame-time targets stay consistent with the flutter-client and voice-canvas reports rather than reinvented; this report's job is enforcement, not re-derivation.
The memory row is new: no earlier report set a whole-app resident figure, only the canvas's own bitmap-cache sub-budget.
Rejected: one combined memory budget spanning idle and active-call states, which hides the real cost driver (LiveKit video buffers and the canvas cache, not base app weight) and gives engineers nothing actionable to fix.
Risk: "mid-tier iOS device" needs a concrete device pinned for CI, reviewed yearly against the oldest iPhone still on the current iOS major version, or the budget drifts meaninglessly upward as the market gets faster.

## 2. Server budgets

Idle RAM for the full self-hosted stack at zero active users: Rust server under 30MB (backend report), Postgres under 60 to 80MB (backend report), LiveKit under 50MB (media report), for a combined baseline under 200MB, extending the backend report's 150MB server-plus-Postgres figure to include the SFU a real deployment also runs alongside it.

One inconsistency worth reconciling now: the Voice Canvas report sets the same Rust server process's idle RSS budget at under 150MB "for the whole process," five times the backend report's under-30MB figure.
Read together, 30MB is the true zero-load baseline and 150MB is the ceiling once the canvas subsystem is loaded with a few channels' candidate lists and spatial-index state resident, not a literal idle figure.
Recommend STRATEGY.md adopt both explicitly and relabel the canvas figure a light-activity ceiling, not idle, so the two stop reading as a contradiction.
With a handful of concurrent voice and canvas participants including one active video room (the media report's up-to-500MB figure), budget the combined stack under 800MB total.
Idle CPU across the stack stays effectively 0%, event-driven, no busy-polling anywhere.

Per-message cost is the number no other report owns, so it is set here: p99 server-side processing time (validate, persist, fan out) for a persisted event under 5ms at small scale, and under 50 microseconds of CPU time for ephemeral relay-only events (typing, presence, avatar and cursor moves) that skip the database entirely.
The steady-state WS fanout hot path (hub lookup plus bounded-channel send) should perform zero heap allocation beyond what is already resident, verified with a `criterion` micro-benchmark plus a periodic (not per-PR) `dhat` allocation-count check.
Rejected: expressing per-message cost only as end-to-end wall-clock latency, which conflates network conditions the server cannot control with the one number the server actually owns: CPU time spent per event.

## 3. Measurement and benchmark infrastructure, from Phase 0

Build this alongside the first working server and client, not after a slowdown is reported.
Server: `criterion` benchmarks on the hot paths named above (event dispatch, permission evaluation, seq assignment, canvas op validation), plus a small Rust WS load-test harness (synthetic connections, scripted message and canvas-op rates) run against a container with fixed CPU and memory limits so results are comparable across machines and over time.
Client: a `flutter drive`/`integration_test` harness timestamping app launch against first-frame and first-interactive callbacks, run in CI on Linux (a pinned runner) and iOS (simulator every PR, real device on a schedule, mirroring the iOS cost-gating pattern already used in the reference codebase's CI).
Frame timing uses Flutter's `FrameTiming` callback directly, exported as p50/p95/p99 plus the jank percentage defined above.
All results land in one versioned JSON baseline file per release, checked into the repo so a human reviews and accepts any budget change in the diff, the same discipline the reference project's `perf-baseline.md` established.

## 4. CI regression gates

Two speeds, matching the project's cheap-per-PR versus periodic-and-heavy CI philosophy.
Per-PR, fast: `criterion`'s built-in baseline comparison fails the build on a Rust hot-path regression past 10%; a small script compares the client's JSON baseline for cold start, warm start, and binary size, failing at 10% for timing and 5% for size, since size regressions compound silently; iOS timing checks run against the simulator only at this stage.
Periodic, heavy: a nightly or pre-release job runs the full WS load test, the real-device iOS timing pass, and a soak test holding an idle server up for an extended period while sampling RSS for a slow leak, mirroring the backend report's own periodic load/soak job rather than duplicating it.
Any threshold breach requires an explicit, reviewed baseline update in the same PR that causes it, never a silent ratchet.
Rejected: gating every PR on the full device-and-load suite, which would make ordinary changes prohibitively slow and expensive on iOS runners specifically, a cost already flagged as real in the reference project's own CI.
Risk: a slow regression that never crosses one PR's threshold, mitigated by the periodic job trending the same JSON baselines over time rather than only diffing the immediately preceding release; and a real-device-only iOS regression can sit in `main` for up to a day before the periodic job catches it, an explicit accepted gap rather than a discovered surprise, revisited once telemetry shows how often simulator and device results actually diverge.

## 5. Profiling workflow per platform

Server, Linux: `cargo flamegraph` or `samply` for CPU hotspots, `tokio-console` for async task stalls and starved executors, `tracing` spans exported to a local OTLP collector in development only, never shipped to production by default.
Client, Linux desktop: Flutter DevTools' CPU and memory profiler, plus Linux `perf`/`sysprof` when the bottleneck sits below the Dart VM in Impeller's native rendering path.
Client, iOS: Xcode Instruments (Time Profiler, Allocations, Core Animation) attached to profile-mode builds specifically, since debug-mode JIT and AOT-compiled profile or release builds behave differently enough that debug-mode profiling actively misleads.
Every profiling session that changes a documented budget updates the relevant report before merge, the same PR-gates-doc-update discipline the reference project's notes name as its single most reusable practice.

## 6. Admin-facing performance metrics

The brief asks for "performance metrics" and to "track performance over time" as an administration requirement.
Verdict: the server exposes the Prometheus `/metrics` endpoint already decided in the backend report, plus a small built-in time-series store (a Postgres table, fixed downsampling: raw for 24 hours, 5-minute averages for 30 days, daily averages for 1 year) that the admin UI reads directly to render graphs with zero extra containers.
This satisfies the requirement out of the box for a self-hoster who never sets up Prometheus, while `/metrics` remains the source of truth for anyone running Grafana.
Tracked series: WS connection count, message and canvas-op throughput, per-event processing latency (the p99 budget from Section 2, made visible, not just enforced in CI), DB pool saturation, and process RSS and CPU sampled every 30 to 60 seconds from `/proc`, avoiding a dependency on `node_exporter` for a number the process can read about itself cheaply.
Rejected: bundling Prometheus and Grafana into the default compose file, too heavy for the "handful of users" default and inconsistent with the backend report's minimal-footprint stance; also rejected, metrics available only via an external stack, which fails the "excellent administration tools" bar for an operator who wants graphs without standing up a second stack.
Risk: a home-grown time-series store duplicates a solved problem; mitigated by keeping its scope deliberately narrow and treating `/metrics` as the escape hatch for anyone who needs more.

## Open questions

- What "mid-tier phone" means concretely for iOS start-time CI, and how often the pinned device should be reviewed as the market moves.
- Whether the built-in admin time-series store should stay Postgres-table-based or move to a dedicated embedded time-series format, once real cardinality and retention needs are known.
- Whether STRATEGY.md should formally adopt the 30MB-idle versus 150MB-light-activity reconciliation proposed in Section 2, since two research reports currently state different numbers for the same process.
