# Performance Program: Adversarial Review

Target document: `docs/research/performance.md`.
Cross-checked against `docs/BRIEF.md`, the sibling reports in `docs/research/` (`backend.md`, `voice-canvas.md`, `voice-canvas-review.md`, `media.md`, `database.md`, `realtime-sync.md`, `security.md`, `devops.md`, `appstore.md`, `networking-relay.md`, `flutter-client.md`).

Severity key: critical findings would force a redesign of the specific budget, metric, or mechanism as written.
Major findings are real defects that should block sign-off until addressed.
Minor findings are worth fixing but do not block the overall direction.

## Critical findings

### 1. The p99 persisted-event budget conflates CPU cost with disk I/O, the exact flaw its own rationale claims to avoid

Section 2 sets "p99 server-side processing time (validate, persist, fan out) for a persisted event under 5ms at small scale."
The same paragraph explicitly rejects measuring per-message cost as end-to-end wall-clock latency, "since that conflates network conditions the server cannot control with the one number the server actually owns: CPU time spent per event."
But "persist" means a Postgres write, and a durable commit is I/O-bound, gated by WAL fsync latency, not CPU time the server code controls.
On the self-host hardware `devops.md` explicitly targets with native arm64 GHCR images, "very often means a Raspberry Pi or other arm64 board," fsync latency on SD-card or low-end network-attached storage routinely exceeds 5ms on its own, before any validation or fan-out CPU work is counted.
This means the budget as worded is not measuring what its own justification says it measures, and it is likely unachievable on the primary self-host target the brief cares most about protecting ("a self-hosted server with only a handful of active users should remain extremely lightweight").
Either redefine the metric to separate CPU-bound validate-and-fan-out time from I/O-bound commit latency, or set a distinct, honestly-I/O-bound commit-latency budget with its own tolerance for slow self-host storage.
As written, the single criterion benchmark this number is meant to drive in Section 3 cannot be built correctly, because it is not clear what the benchmark should actually measure.

### 2. The Section 3 benchmark target list still names a mechanism two sibling reports already killed

Section 3 lists "seq assignment" among the hot paths that need a dedicated `criterion` benchmark, alongside event dispatch, permission evaluation, and canvas op validation.
That phrasing matches `voice-canvas.md`'s original design, a per-channel monotonic `seq` counter assigned inside the write transaction.
`database.md` explicitly overrides that design: "`id` supersedes that report's separate per-channel `seq` counter... A snowflake ID is generated in-process with no database round trip and no shared counter, so concurrent writes to the same channel no longer serialize on ID allocation."
`realtime-sync.md` independently reaches the same conclusion and specifies the same global snowflake scheme.
`voice-canvas-review.md` already flags this as its own critical finding 1, calling the per-channel counter "the worst possible bottleneck precisely for the scenario the Voice Canvas exists to support."
`performance.md` was written in the same research pass but was not synced to that reconciliation: it still lists "seq assignment" as a benchmark-worthy hot path, language that only makes sense for the contended, lock-based counter design that was rejected, not the lock-free, in-process snowflake generator that replaced it.
If Phase 0 benchmark work is built literally against this list, engineering time goes into micro-benchmarking contention on a mechanism that is not being shipped, or the benchmark gets silently redefined by whoever implements it with no documentation trail, reproducing the exact "which report is the accidental authority" failure mode this same report calls out for the RSS-budget conflict in Section 2.
Fix the hot-path list to match the snowflake-ID reconciliation before Phase 0 benchmark work starts.

## Major findings

### 3. The admin time-series store taxes the idle budget Section 2 just set, with no budget line of its own

Section 6 adds a background-sampled Postgres time-series table (WS connection count, throughput, per-event latency, DB pool saturation, RSS and CPU every 30 to 60 seconds) with fixed downsampling (raw 24h, 5-minute averages 30d, daily averages 1y).
This is continuous write load, continuous storage growth, and a continuous downsampling sweep running inside the exact process and exact Postgres instance Section 2 just budgeted at under 30MB (Rust) and under 60 to 80MB (Postgres) idle.
No line item anywhere accounts for this feature's own RAM, CPU, or disk cost against those figures.
At even modest sample counts, raw 24-hour retention across five-plus tracked series sampled every 30 to 60 seconds is tens of thousands of rows before the first downsample runs, adding to shared buffer pressure on the same tiny, tuned-for-a-handful-of-users Postgres instance `database.md` sized for message and canvas data, not for a self-inflicted monitoring workload.
The report's own risk note ("a home-grown time-series store duplicates a solved problem") treats this as a one-time build-cost concern; the real cost is the ongoing operational tax against the numbers this same document just finished setting two sections earlier.

### 4. The 30MB-versus-150MB reconciliation is asserted, not decomposed

Section 2 resolves the backend-versus-voice-canvas RSS conflict by declaring 150MB "a light-activity ceiling... once the canvas subsystem is loaded with a few channels' candidate lists and spatial-index state resident," rather than a literal idle figure.
No component breakdown backs the claimed 120MB delta: no accounting for how much of it is the grid spatial index, in-flight candidate lists, WS buffers, or anything else.
This report's own Section 3 mandates that "all results land in one versioned JSON baseline file per release, checked into the repo," and Section 4 states "any threshold breach requires an explicit, reviewed baseline update in the same PR that causes it, never a silent ratchet."
An unverified guess that happens to be first to land in that baseline becomes the accepted number by construction, the same "accidental authority" failure this section explicitly names as the risk of leaving the conflict unresolved.
Relabeling a contradiction as reconciled is not the same as measuring it; the reconciliation should be flagged as provisional pending an actual measured breakdown, not presented as settled enough for STRATEGY.md sign-off.

### 5. No battery budget anywhere, despite battery being an explicitly named brief metric

The brief's Performance Requirements section lists "Battery impact" as one of the things to "constantly evaluate," on equal footing with memory, CPU, and network usage.
Section 1's client budget table has cold start, warm start, memory, app size, frame time, and jank, and zero battery or thermal figures.
Section 5's profiling workflow lists Xcode Instruments' Time Profiler, Allocations, and Core Animation for iOS, but never Energy Log or a thermal-state check, and never mentions `powertop`/`turbostat` for Linux.
This is a real gap given the app's heaviest features (voice calls, video, screen share, a 60fps canvas with camera-bubble video textures) are precisely the workloads that drain batteries fastest, and none of this program's Phase 0 measurement infrastructure, CI gates, or JSON baseline schema has a place to put a battery number even if one were set later.

### 6. No network-usage or disk-usage client budget, despite both being explicitly named brief metrics

The brief lists "Efficient network usage" as a Core Principle and "Network usage" and "Disk usage" as Performance Requirements to constantly evaluate.
This report sets a server-side per-message CPU-processing budget and a WS fanout allocation target, but no client-facing bytes-on-wire budget (idle heartbeat overhead, typical session data usage, canvas late-join fetch cost beyond the canvas report's own 500KB figure).
Disk usage is covered only as compressed app/binary size; nothing bounds growth of the client's Drift database, attachment cache, or logs over time, and no other report (including `flutter-client.md`) sets one either.
Concrete failure: a self-hoster's phone or a long-lived desktop install with keep-forever message retention (`database.md`'s default) and no client-side eviction policy accumulates unbounded local storage with no budget, gate, or admin-visible signal anywhere in this program to catch it.

### 7. Timing-based CI gates have no stated repeat-run protocol, and the jank budget has no minimum sample size

Section 4's per-PR gate fails the build at a 10% timing regression (cold start, warm start) and 5% size regression, and Section 1's jank budget is "fewer than 1% of frames exceed 2x the frame budget, measured over a rolling session."
Neither specifies multiple trials, median-of-N, or outlier discarding for the timing gates, on GitHub-hosted shared runners known for CPU-steal noise; a single noisy run can trip or mask a 10% threshold on a 500ms warm-start target (50ms of slack) without any code change being at fault.
The jank budget has the same problem in a different shape: "under 1%" with no minimum frame-count floor means a short `flutter drive` session (a few dozen to a hundred frames) makes the threshold either trivially unhittable (0 janky frames required) or noise-dominated, and the report gives no guidance on session length or frame count needed to make the number statistically meaningful.
Both gaps risk chronic CI flakiness, directly undermining the "explicit, reviewed baseline update" discipline the whole two-speed CI design depends on, and eroding trust in the gate the same way an unenforced one would.

### 8. iOS App Extensions have hard OS memory ceilings this program never measures or gates

The client's push-decryption Notification Service Extension (`networking-relay.md`) and the ReplayKit Broadcast Upload Extension for screen share, capped at roughly 50MB (`media.md`, `appstore.md`), run as separate OS-limited processes with hard kill ceilings, not soft targets.
Section 1's client budget table and Section 5's profiling workflow address only the main app process; there is no extension-process memory line item, and Xcode Instruments attach targets are described only for "profile-mode builds" of the app itself, not for attaching to an extension process, a different Instruments workflow.
A hard kill of an extension is not a degraded-but-working state like a main-app memory overshoot would be; it is an instant, silent failure (screen share drops mid-session, push notifications stop decrypting) that is currently invisible to every measurement and CI-gate mechanism this program defines.
Given the canvas report's own L3 layer already builds a bounded LRU decoded-bitmap cache that a future contributor could plausibly reuse or adapt inside the broadcast extension for frame buffering, the 50MB extension ceiling deserves its own explicit budget line and its own periodic gate, not silent omission.

### 9. "Real-device iOS timing" names no device-farm infrastructure

Section 4's periodic job includes "the real-device iOS timing pass," and Section 3 mentions "real device on a schedule."
GitHub Actions provides iOS simulator runners on its hosted macOS images, not real physical device runners; getting real-device timing numbers requires either a physical Mac-mini-plus-iPhone lab, a paid third-party device farm (Firebase Test Lab, BrowserStack App Live, AWS Device Farm), or a service like Xcode Cloud with device support.
Neither this report nor `devops.md`'s CI pipeline section names, provisions, or budgets for any of these; `devops.md` covers iOS artifact building and TestFlight upload in detail but has no device-farm or lab-hardware section at all.
As written, "real-device iOS timing" is a line item with no described way to actually run it, which matters given `devops.md`'s own observation that macOS runners already cost roughly 10x Linux ones, a cost that stacks further with any device-farm service fee this report never surfaces.

## Minor findings

### 10. "Effectively 0% idle CPU" has no corresponding CI gate

Section 2 asserts idle CPU across the stack stays "effectively 0%, event-driven, no busy-polling anywhere," but Section 4's periodic job list (WS load test, real-device iOS timing, RSS soak) checks memory and timing, never CPU utilization at idle.
A regression that introduces a busy-poll loop or a too-tight retry timer would breach this stated target with no automated mechanism, at any CI speed, to catch it.

### 11. ProMotion is Apple-only vocabulary with no Linux equivalent, on a project that names Fedora a primary testing environment

Section 1's frame-time row sets "under 8.3ms on ProMotion (120fps)" with no equivalent figure for high-refresh-rate Linux desktop monitors, common among the Fedora developer audience the brief names as a primary test platform, and the Linux `flutter drive` CI runner's own display and refresh characteristics are unspecified.
Given `flutter-client.md`'s own risk note that Impeller is "still evolving" on Linux specifically, a frame-time gate silently tuned only to a 60Hz assumption on a headless CI runner could pass while missing real jank on a 144Hz Fedora desktop the brief's own primary testers are likely to use.

### 12. Android is silently absent from every budget and the profiling workflow, with no stated plan for when it arrives

Section 1's budget table and Section 5's profiling workflow cover Linux and iOS only; Android, a stated v1 client platform in the brief, has no budget row, no profiling tooling section (Android Studio Profiler or Perfetto, a materially different device-fragmentation problem than one pinned "mid-tier iPhone"), and no mention in the open questions list.
This is defensible given the brief's own Linux-and-iOS launch priority and `flutter-client.md`'s "designed now but not built until that phase" stance on Android, but the omission should be a stated, deliberate deferral in this report's open questions, not a silent gap a reader has to infer from a sibling document.

## A security gap this report's own recommendation creates

Section 6 builds an admin UI that reads the new time-series table directly and reaffirms `/metrics` as "the source of truth for anyone running Grafana," but neither this report, `backend.md`'s observability section, nor `security.md`'s five enumerated trust boundaries (client-server, client-relay, server-relay, client-client media, supply chain) state an access-control requirement for `/metrics` or the new admin time-series read path.
WS connection counts and per-event throughput are activity and timing metadata, exactly the category `security.md` and the brief's networking section both treat as sensitive ("the architecture minimizes metadata exposure").
An open Prometheus `/metrics` endpoint is a common real-world misconfiguration; a self-hoster following the "production-ready docker-compose example" `devops.md` promises has no documented guidance here about network-isolating or auth-gating the scrape endpoint before exposing it.
This is a gap the performance report itself introduces by building a second, admin-UI-facing consumer of the same data, and it should not ship without an explicit access-control statement.

## Open questions the specialist should have raised but did not

- What does the p99 persisted-event budget actually measure once CPU-bound validation and fan-out are separated from I/O-bound Postgres commit latency, and what is the separate, honestly-I/O-bound budget for self-hosted hardware like a Raspberry Pi (see finding 1)?
- Has the Section 3 hot-path benchmark list been reconciled against the snowflake-ID scheme `database.md` and `realtime-sync.md` settled on, replacing "seq assignment" with whatever the actual lock-free mechanism needs measured, if anything (see finding 2)?
- What is the RAM, CPU, and disk cost of the Section 6 admin time-series store itself, measured against the idle budgets Section 2 sets for the same process (see finding 3)?
- What battery, network-usage, and client disk-usage budgets satisfy the brief's own named Performance Requirements, none of which this report currently sets (see findings 5 and 6)?
- What memory budget and profiling workflow apply to the iOS Notification Service Extension and Broadcast Upload Extension processes, given their hard OS-enforced kill ceilings (see finding 8)?
- What concrete infrastructure runs "real-device iOS timing," and what does it cost on top of the macOS runner premium `devops.md` already flags (see finding 9)?
- What access control protects `/metrics` and the new admin time-series endpoint from unauthenticated metadata exposure (see the security gap above)?
