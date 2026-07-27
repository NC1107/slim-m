# Voice Canvas Client Spike: Spatial Culling and the Off-Riverpod Hot Path

Status: Phase 5 spike result, measured 2026-07-26.
Scope: the two client-side bets in the Phase 5 deliverables, namely in-memory uniform-grid viewport culling at the soft-cap object counts, and an off-Riverpod `ChangeNotifier` feeding the paint layer with no `StreamProvider` in the render loop.
The server-side R-Tree viewport query, the viewport-delta subscription protocol, the LiveKit subscribe and unsubscribe hysteresis, and world-coordinate presence placement are the other half of Phase 5 and are not covered here.

Verdict up front: **both bets hold, and neither holds for the reason the plan assumed.**
Culling fits the frame budget with about three orders of magnitude of headroom, but so does a brute-force linear scan, so the grid is not what buys 60fps.
What the grid actually buys is protection above the soft caps, and it introduces one catastrophic failure mode of its own that the plan does not mention and that a linear scan does not have.
The Riverpod bet holds decisively, but the number that proves it is a rebuild count, not a dispatch cost.

## What was measured, and on what

Hardware: AMD Ryzen 9 9950X3D, 8 cores visible to this environment, 32GB RAM, Fedora 44 KDE Plasma on Wayland.
Toolchain: Flutter 3.44.8 stable, Dart 3.12.2.

Two harnesses, both committed under `client/packages/voice_canvas/benchmark/`, following the same split the server side already uses with criterion: the benchmarks live next to the code, they are compiled by `dart analyze` on every run, and they are executed on demand rather than on every CI push.
`flutter test` with no arguments only collects `test/`, so neither harness runs as part of the normal suite.

```sh
cd client/packages/voice_canvas

# Bet 1. AOT is the number that matters; see the JIT caveat below.
dart compile exe benchmark/spatial_grid_benchmark.dart -o /tmp/grid && /tmp/grid
dart run benchmark/spatial_grid_benchmark.dart --json   # machine-readable

# Bet 2. Needs the real widget pipeline, so flutter test hosts it.
flutter test benchmark/hot_path_benchmark.dart
```

### How the harness controls for measuring itself

Five things, because a microbenchmark that measures its own scaffolding is worse than no benchmark.

- **Adaptive batch sizing.**
  Each case is warmed for 150ms, the per-op cost is estimated from that, and the batch is then sized so one batch spans at least 25ms.
  The `Stopwatch` read and the loop counter are therefore a vanishingly small share of each sample rather than most of it, which is the failure mode of timing a single call.
- **Median of nine batches, not a mean.**
  The mean of a timing distribution is dragged by scheduler noise in one direction only.
- **A checksum sink.**
  Every measured body returns an int that is XORed into a global.
  Without it the optimizer is free to delete a pure query whose result is discarded, and the benchmark then reports the cost of an empty loop.
- **AOT as well as JIT.**
  `dart run` is JIT; a shipped Flutter release build is AOT.
  These disagree, and not by a constant factor: AOT is about **2x slower than JIT for grid queries** and **identical for the linear scan**.
  The difference is the hashed cell lookup, which JIT specialises with type feedback and AOT does not.
  Every grid number below is AOT, because that is what ships.
  Quoting the JIT figure would have understated the shipping cost of the grid by half while leaving its competitor untouched, which would have inverted part of the conclusion.
- **A pure-Dart index.**
  `lib/src/spatial_grid.dart` imports no `dart:ui` and no Flutter, so the benchmark runs on the plain Dart VM with no engine, no binding, and nothing else in the isolate.
  A test enforces this boundary rather than trusting it.

Run-to-run spread across repeated runs was under 3% for every case except the linear scan at 20,000 objects, which sits on a cache boundary discussed below and varies by about 10%.

### The budget this is held to

60fps is a 16.6ms frame.
Culling is asked to fit **1ms, about 6% of the frame, as a hard ceiling, with 0.25ms (1.5%) as the target.**

The reasoning: that 16.6ms is the UI thread's, and it is already shared by Flutter's own build, layout, and paint-recording phases plus, per the plan, five render layers and a decoded-bitmap cache.
Culling produces no pixels.
It is bookkeeping that decides what the pixel-producing work will be.
Spending more than a few percent of the frame deciding what to draw, rather than drawing, is the point at which the index has stopped paying for itself.
6% is generous for that role and 1.5% is where it should actually land.

## Bet 1: uniform-grid culling

### Throughput at the soft caps

The world here is `hotspot`: 80% of objects inside a plus or minus 6,000px working region and 20% scattered over the full plus or minus 5,000,000px bounded world.
That is the realistic shape, and it is the one the plan's "20,000 objects across a 10,000,000px world" concern is really about.
Viewport is 2560x1440 at zoom 1.
Cell size 2048px, per the plan.

| Objects | Visible | Grid (AOT) | Linear (AOT) | Grid, % frame | Linear, % frame |
|---|---|---|---|---|---|
| 1,000 | 29 | 0.74 us | 1.29 us | 0.004% | 0.008% |
| 5,000 (**iOS soft cap**) | 140 | 3.82 us | 6.63 us | 0.023% | 0.040% |
| 10,000 | - | 7.94 us | 13.03 us | 0.048% | 0.078% |
| 20,000 (**Linux soft cap**) | 536 | 15.6 us | 26.4 us | 0.094% | 0.159% |
| 30,000 | - | 23.5 us | 152.1 us | 0.141% | 0.916% |
| 40,000 | - | 34.5 us | 256.4 us | 0.208% | 1.545% |
| 50,000 | 1,397 | 45.6 us | 361.8 us | 0.274% | 2.179% |
| 100,000 | 2,759 | 142.0 us | 763.7 us | 0.855% | 4.601% |

**At both soft caps, both structures fit the budget with room to spare.**
At the Linux cap of 20,000 the grid costs 0.094% of a frame and the linear scan 0.159%.
That is 64x and 38x inside the 1ms ceiling respectively, and over 600x inside the frame.
The grid's advantage over doing nothing clever at all is 1.7x, on a quantity that is already negligible.

This desktop is not an iPhone.
Taking a deliberately pessimistic 5x for a mid-range mobile core on scalar float work, the iOS cap of 5,000 objects lands at 19 us for the grid and 33 us for the linear scan, still 0.2% of a frame.
**The soft caps are not where this breaks.
Nothing about culling threatens 60fps at 5,000 or 20,000 objects, by either method.**

Where it does break: the grid stays inside the 1ms ceiling to roughly **700,000 objects** by extrapolation from the near-linear region, and the linear scan to roughly **130,000**.
Neither is a limit anyone will meet.

### The cache knee, and why the 20,000 linear figure flatters itself

The linear scan is flat at 1.29 ns per object up to 20,000, then jumps to 5.07 ns at 30,000 and settles near 7.6 ns.

That knee is not algorithmic.
Bounds are stored as four doubles per object, so 20,000 objects is 640KB and 30,000 is 960KB, against a 1MB L2 on this part.
Below the knee the benchmark re-scans an array that never leaves L2; above it, every pass streams from L3.
The knee lands exactly on the cache boundary.

This matters for honesty about the table: **the sub-20,000 linear-scan numbers are the best case that structure will ever see**, because the benchmark hands it a fully L2-resident array and asks the same question hundreds of times in a row.
A real frame shares that cache with Flutter's own working set, the decoded-bitmap cache, and everything else.
The realistic per-object figure is the post-knee 7.6 ns, which puts a linear scan at 20,000 objects nearer **152 us, 0.9% of a frame** - still inside budget, but with 6x less headroom than the naive reading suggests.

The grid does not have this problem to the same degree, because it only touches the candidates it selects.
It has a milder version of it: its per-candidate cost is about 7.2 ns, essentially the random-access figure, since candidate slots are scattered through the same array.

### The bad cases

This is where the two structures stop being interchangeable.
All at cell size 2048, AOT.

| Case | Objects | Visible | Candidates | Dup factor | Grid | vs linear |
|---|---|---|---|---|---|---|
| `uniform`, sparse board | 20,000 | 34 | 131 | 1.30 | **1.16 us** | 23x faster |
| `hotspot`, realistic | 20,000 | 536 | 2,060 | 1.29 | **15.0 us** | 1.8x faster |
| `oversized`, objects 8 cells wide | 20,000 | 2,549 | 3,166 | **81.0** | **66.8 us** | 2.5x slower |
| `clustered`, all in one cell | 20,000 | 14,127 | 20,000 | 1.00 | **224.8 us** | **8.5x slower** |

- **Clustered is the grid's worst realistic case and it loses badly.**
  With every object in one bucket the broad phase degenerates to a full scan, and then pays extra for the bucket indirection and the deduplication stamp on top.
  224.8 us against the linear scan's 26.4 us on the same data.
  Still only 1.4% of a frame, so it is not a correctness or a 60fps problem, but it is the grid being 8.5x worse than no grid at all.
  A canvas where everyone works in the same small area, which is the normal way people use a shared board, is exactly this shape.
- **Oversized objects cost index size, not query time.**
  Objects eight cells across occupy 81 buckets each, so the index holds 1.62M entries for 20,000 objects.
  Query time stays reasonable because the candidate set is still close to the visible set (3,166 for 2,549).
  The cost is memory and insert time.
  Screen-share tiles and large pasted images are exactly this shape, and the plan's mip-tier cache thinking should extend to the index: a 5,000px screen-share tile at 2048px cells is not a pathological input, it is a Tuesday.
- **Sparse boards are where the grid earns its keep**, 23x, and this is the case the plan was designed around.
  It is real, it is just not the expensive one.

### Zooming out is the failure mode nobody wrote down

A uniform grid probes every cell the viewport covers, whether or not anything is in them.
Pull the camera back and that count grows with world area while the object count does not move.

| Zoom | Viewport | Cells probed | Visible | Raw grid | Adaptive |
|---|---|---|---|---|---|
| 1.0 | 2,560px | 4 | 536 | 15.0 us | 15.0 us |
| 0.1 | 25,600px | 112 | 16,054 | 217 us | 217 us |
| 0.01 | 256,000px | 9,072 | 16,057 | 317 us | 317 us |
| 0.001 | 2,560,000px | 880,704 | 16,194 | **11,826 us** | **72 us** |
| fit world | 10,000,000px | 23,843,689 (analytic) | 20,000 | not measurable | 207 us |

**At zoom 0.001 the raw grid costs 11.8ms, which is 71% of the entire frame budget, to find 16,194 objects a linear scan finds in 26 us.**
Framing the whole bounded world would require 23.8 million cell probes per frame.
That is not a slow frame, that is a hung application, and it is reachable by a user holding a pinch gesture.

The fix is three lines and is implemented and tested: compare the cell span against the object count and run the linear scan when the broad phase would do more work than simply testing everything once.
`UniformGrid.query` does this and reports which branch it took.
It turns 11.8ms into 72 us, a **164x** improvement, and it is what makes the whole-world case measurable at all.

This is the single most important result of the spike.
**The plan as written, implemented literally, has a reachable frame-time cliff of two orders of magnitude, and the mitigation is trivial once you know to look.**
It would not have been found by benchmarking the happy path, which is what "prove 60fps at 20,000 objects" invites you to do.

### Cell size

At 20,000 objects, `hotspot`, AOT.
Query cost is the cull; build cost is a full index rebuild.

| Cell | Candidates for 536 visible | Cells probed | Occupied cells | Dup factor | Query | Build |
|---|---|---|---|---|---|---|
| 256 | 623 (1.16x) | 66 | 20,424 | 4.51 | 16.9 us | 5,230 us |
| 512 | 864 (1.61x) | 24 | 10,261 | 2.45 | 11.9 us | 2,770 us |
| **1024** | 1,103 (2.06x) | 8 | 6,610 | 1.63 | **10.5 us** | 1,642 us |
| 2048 (planned) | 2,060 (3.84x) | 4 | 5,163 | 1.29 | 15.1 us | 1,311 us |
| 4096 | 8,042 (15.0x) | 4 | 4,509 | 1.15 | 70.0 us | 1,179 us |
| 8192 | 16,054 (30.0x) | 4 | 4,221 | 1.05 | 143.7 us | 1,114 us |
| 16384 | 16,054 (30.0x) | 4 | 4,073 | 1.05 | 142.5 us | 1,042 us |

**The optimum is 1024px, and the plan's 2048px costs 44% more query time.**
Both are fine against the budget; this is a choice between 0.063% and 0.091% of a frame.

**The sensitivity is sharply asymmetric, and that is the finding worth keeping.**
Measured against the 1024px optimum, one octave either side is mild: 1.13x at 512 and 1.44x at 2048.
Two octaves is where the two directions part company: 1.61x at 256, against 6.7x at 4096.
Three octaves too large is 13.7x, and there is no corresponding cliff going the other way.
Above 4096 a single cell swallows the entire working hotspot and the candidate set stops shrinking at all, which is the flat 16,054 in the last two rows: the broad phase has stopped filtering and is returning everything.

So: **err small.**
The cost of a cell too small is a mild, bounded penalty in query time plus a real penalty in build time and memory (5.2ms and 20,424 cells at 256px, against 1.3ms and 5,163 at 2048px).
The cost of a cell too large is unbounded degradation toward "no index at all, plus overhead".

1024px is the recommendation: it is the measured query optimum, its build cost (1.64ms) is 25% above the cheapest, and it sits an octave clear of the cliff edge rather than on it.

One caveat on transferring this number.
The optimum tracks the ratio of cell size to typical object size, and objects here are 64-512px.
If the real canvas skews larger, the optimum moves with it.
The shape of the curve, flat-then-cliff, is what transfers; the specific 1024 should be re-measured against real object-size telemetry, which the plan already intends to collect.

### The thing the index cannot currently do

**A full rebuild at 20,000 objects costs 1.3 to 1.6ms, about 8 to 10% of a frame.**
That is affordable once on channel load.
It is not affordable per frame, and this index has no `remove` or `move`.

Dragging an object is the canvas's most obvious interaction and it changes an object's cells.
Incremental update needs to land before any of this is real.
It is not hard, but it is not free either: removing a slot from a bucket is O(bucket length), and the `oversized` case says one object can sit in 81 buckets, so a drag of a large screen-share tile touches 162 buckets per frame.
This is a known gap, deliberately not solved in a spike, and it is the first thing Phase 6 should build and measure.

## Bet 2: keeping Riverpod out of the render loop

This bet holds, and the evidence that matters is not a timing.

### Dispatch cost, which turns out to be the wrong question

`flutter test` hosted, debug JIT.

| Path | Per update |
|---|---|
| `ChangeNotifier.notifyListeners()` | 15 ns |
| Riverpod `StateProvider` + `container.listen` | 197 ns |
| ratio | **13x** |
| `CanvasScene.recull()` + notify, 1 object | 59 ns |
| `CanvasScene.setViewport()` + notify, 20,000 objects (sparse, 36 visible) | 654 ns |

13x looks decisive and is close to meaningless.
197 ns is 0.001% of a frame.
**If provider dispatch were the only cost, Riverpod in the render loop would be perfectly fine**, and any argument resting on this number is an argument the measurement does not support.

### The actual cost: rebuilds

Same 600 updates through two minimal trees, differing only in how the viewport reaches the painter.
A no-op control establishes the harness floor so `pump()` overhead is visible rather than silently included in both.

| Path | Widget builds | Paints | us/frame | over floor |
|---|---|---|---|---|
| `pump()` floor, nothing changing | - | 0 | 23.4 | - |
| `CustomPainter(repaint: scene)` | **0** | 600 | 107.8 | 84.4 |
| `ConsumerWidget` watching a provider | **600** | 600 | 195.1 | 171.7 |

**Zero widget builds against 600, for identical visual output.**
That is exact, machine-independent, and it is the whole argument.
A `CustomPainter` constructed with `repaint: scene` subscribes the render object directly to the `Listenable`; a notification marks it dirty for paint and the element tree is never touched.
The provider path rebuilds a widget, reconciles an element, and allocates a new painter every frame, and only then paints the same thing.

The timing column is a **debug JIT build with assertions on** and should not be read as a release frame cost.
Release AOT would be far cheaper on both rows.
The ratio is what survives: the provider path costs 2.0x the repaint-only path over the harness floor, on the smallest tree that can tell them apart, a single `Directionality` over a `RepaintBoundary` over a `CustomPaint`.
A real canvas widget subtree is much larger and that multiplier grows with it.
Of the 172 us the provider path spends above the floor, 84 us is the repaint the other path also pays, and the remaining **87 us is the rebuild itself, for one widget**.
Take that as a floor, not an estimate.

### StreamProvider is structurally disqualified, not merely slow

The roadmap says no `StreamProvider` in the render loop.
It is right, and the reason is sharper than performance.

- `ChangeNotifier` listeners run **synchronously, inside the same call** that changed the state.
  Measured: 1 listener invocation, before the mutating call returns.
- A `StreamProvider` value is **not observable until the event loop turns.**
  Measured: 0 before, 1 after.

A stream cannot deliver a value to the paint layer within the frame that produced it, whatever it costs.
Feed a pointer-move through a `StreamProvider` and the canvas renders it one frame late, every frame - 16.6ms of added input latency on a drag, permanently, and invisible to any throughput benchmark.
**This is a correctness property of the architecture, not a performance tradeoff, and it is the strongest reason of the three to keep the render loop off Riverpod.**

### Making the boundary enforced rather than intended

`flutter_riverpod` is a **dev dependency** of `slimm_voice_canvas`, not a dependency.
The package cannot import it; the benchmark and the tests can.
Two tests keep it that way, parsing import and export directives rather than grepping raw text, so a doc comment naming a package the code deliberately avoids does not read as a dependency on it (the first draft of both checks failed exactly that way):

- no file under `lib/` imports Riverpod
- `lib/src/spatial_grid.dart` imports neither `dart:ui` nor `package:flutter/`, which is what keeps it AOT-benchmarkable outside the engine

And the regression test that matters: 20 viewport changes through `RepaintOnlyCanvas` must produce **0 widget builds**.
If someone later routes the viewport through a provider, that test fails and names the reason.

## What I would do differently

1. **Ship the adaptive fallback, not the uniform grid.**
   The plan's structure has a reachable 11.8ms frame.
   `UniformGrid.query` picking between broad phases on cell-span-versus-object-count is the actual deliverable, and the grid alone is not safe to build on.
   This is the redesign this phase existed to surface.
2. **Move the cell size to 1024px**, and treat the number as provisional pending real object-size telemetry.
   Err small if unsure: too-small is a bounded penalty, too-large degrades without limit.
3. **Reconsider whether the index is worth its complexity at the stated caps.**
   At 20,000 objects the grid saves 11 us per frame, 0.07% of the budget, and costs: a hash map, a duplication factor, a deduplication stamp, a 1.3ms rebuild, an unimplemented incremental-update path, an 8.5x regression in the clustered case, and a two-order-of-magnitude cliff needing its own mitigation.
   A linear scan over two typed arrays is about 20 lines, has no bad cases, no cell size to tune, no rebuild, and makes movement a two-float write.
   **If the soft caps are the real target, the linear scan is the better engineering choice**, and the grid should be introduced behind the same adaptive seam if and when telemetry shows counts heading past 30,000.
   The seam is already there and reports which branch it took, so this is a runtime decision rather than a rewrite.
   Owner call, since it trades measured simplicity against headroom nobody has asked for yet.
4. **Build incremental update before anything else in Phase 6.**
   A spatial index that only supports bulk rebuild does not support dragging, which is the canvas's primary interaction.
5. **Set the mobile numbers on a real device.**
   Everything here is one desktop core.
   The iOS extrapolation is a 5x guess, and the roadmap's 5,000-object iOS cap is the one that has never been measured on the hardware it describes.
   The harness AOT-compiles and needs no engine, so it will run on a device as-is.
6. **Extend the `oversized` finding to the index budget.**
   Screen-share tiles and large images multiply index entries by up to 81x at 2048px cells.
   The plan budgets the decoded-bitmap cache and does not budget the index.

## Exit criteria status

| Phase 5 client criterion | Status |
|---|---|
| 60fps culling at 5,000 (iOS soft cap) | **Met on desktop AOT**, 3.8 us, 0.02% of frame. Not yet measured on an iPhone. |
| 60fps culling at 20,000 (Linux soft cap) | **Met**, 15.6 us, 0.09% of frame, on the Fedora KDE Wayland target. |
| Off-Riverpod `ChangeNotifier` feeds the paint layer | **Met**, 0 widget builds across 600 viewport changes, enforced by test. |
| No `StreamProvider` in the render loop | **Met**, and shown to be a correctness requirement rather than a preference. |
| A documented redesign, if the structure is wrong | **Produced**: the adaptive fallback, the 1024px cell size, and an open question about whether the index is warranted at these counts. |

Not covered by this spike, and still open in Phase 5: the server-side R-Tree viewport query and the viewport-delta subscription protocol, LiveKit subscribe and unsubscribe hysteresis near the viewport boundary, and world-coordinate presence placement with recenter-on-drift far from the origin.
Note that recenter-on-drift interacts with everything measured here, since rebasing the render matrix invalidates cell keys; the index was measured in absolute world coordinates throughout.
