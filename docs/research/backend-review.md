# Backend and Server Architecture: Adversarial Review

Status: pre-implementation critique of `docs/research/backend.md`.
Scope: the same axes the report itself covers, plus consistency against the brief and the sibling research reports it should have been reconciled with (`realtime-sync.md`, `database.md`, `security.md`, `devops.md`, `voice-canvas.md`, `media.md`).
Severity is reserved for "critical" only where the finding would force a redesign before implementation starts.

## Summary

The report is well argued on its own terms, but it was written without reconciling two decisions that sibling reports in the same folder have already overridden: the ordering mechanism (`seq.rs` versus the snowflake ID scheme `realtime-sync.md` and `database.md` settled on) and the auth token model (stateless JWT versus the opaque, revocable session tokens `security.md` settled on for exactly the reason this project cares about moderation).
Both are foundational, hard-to-retrofit choices, and both are wrong as currently written, not because the reasoning inside `backend.md` is bad, but because a more recent, better-justified decision exists elsewhere in the same document set and was not incorporated.
Beyond those two, the report also carries forward an "open question" on moderation and content encryption that `security.md` already closed, and a second "open question" on Apple guidelines that `security.md` also already closed, meaning roughly a third of the report's own stated open questions are stale.
There is also a real, unweighed long-term cost to the two-language strategy, and a horizontal-scaling gap in the WebSocket hub that the report never surfaces as even a question, unlike the rate limiter and the ID scheme, which both got that treatment elsewhere.

## Critical findings

### 1. `seq.rs` reintroduces the exact bug class it claims to fix

Target: the `ws/seq.rs` module described in backend.md section 2, "server-assigned monotonic sequence numbers per conversation/per-canvas."

Weakness: `database.md` explicitly considered this design, `voice-canvas.md`'s own per-channel `seq bigint` "assigned via `SELECT ... FOR UPDATE`," and rejected it by name.
`database.md` states plainly that this is "the same lock-then-append pattern that caused echo-messenger's TOCTOU bug, because every write still contends on one counter row per channel," and adopts a global, in-process, 64-bit snowflake ID instead, generated with no database round trip and no shared counter row.
`realtime-sync.md` independently reaches the same conclusion and states the snowflake ID is "used as the identity and ordering key for every persisted event in the system, not just messages," explicitly including canvas ops.
`backend.md` was written as if this question were still open, naming a `seq.rs` module and describing exactly the per-conversation/per-canvas counter design that its own sibling reports evaluated and discarded.

Failure mode: if `seq.rs` is implemented literally as backend.md describes, a lively voice-canvas session with several people drawing at once serializes every stroke, image move, and window drag onto one lock per channel, reproducing the contention and TOCTOU risk that is the single most-cited lesson from echo-messenger throughout every sibling report.
The testing-strategy section compounds this: it proposes property-based tests for "seq convergence," testing convergence of a mechanism the rest of the project has already moved past.

Resolution: remove `seq.rs` from the module boundary plan.
Adopt the shared snowflake ID generator, likely living in `db/` or a new `ids/` module, as the single identity and ordering mechanism for every persisted event type, matching `realtime-sync.md` and `database.md` exactly.
Update the testing-strategy section to target snowflake ID convergence and monotonic-clock-guard behavior, not a `seq.rs` counter that should not exist.

### 2. JWT access tokens contradict the security report's revocation model

Target: the `auth/` module described in backend.md section 2, "JWT access (15 min) and refresh (7 day) issuance."

Weakness: `security.md` independently designed the auth token model and reached a different, explicitly justified verdict: "opaque server-side session tokens, not stateless JWTs," with a 1-hour access token and a 60-day refresh token, because "the server is already stateful, a session lookup is one indexed query, and opaque tokens give instant revocation... while avoiding every JWT footgun."
That rationale is not a stylistic preference, it is aimed directly at this project's own stated requirement for "excellent moderation tools" and an admin device list that can kill a session immediately.
`backend.md`'s auth surface section gives no justification for choosing JWT over opaque tokens at all: it only says the design "reuses echo's proven ticket pattern," but the WS ticket mechanism (both reports agree on this part) is orthogonal to what backs REST-level session authentication, which is the part where the two reports actually diverge.

Failure mode: an admin bans an abusive user or an operator revokes a stolen device from the in-app device list.
Under `backend.md`'s literal design, that user's already-issued JWT access token keeps authenticating requests for up to 15 minutes, because nothing server-side can invalidate a JWT before its natural expiry.
This is not an edge case that a later patch fixes, it is a structural property of stateless JWTs, and it directly undermines the "instant revocation" the sibling security report identifies as the reason to avoid JWTs in the first place.
A 15-minute access token also means up to roughly four times more token-refresh network round trips per day than `security.md`'s 1-hour token, each one waking the radio on a battery-powered mobile client, working against the brief's explicit battery and network-efficiency goals.

Resolution: pick one token model for the whole project.
Adopt `security.md`'s opaque, hashed, instantly revocable session token, since it is the design that actually satisfies the brief's moderation and admin requirements, and correct the `auth/` module description and the authentication-surface section of `backend.md` to match.

## Major findings

### 3. The WebSocket hub has no horizontal-scaling story, and does not even flag the gap

Target: `ws/hub.rs`, "connection registry keyed by user and device, true multi-device fan-out" (backend.md section 2), against the brief's "official hosted service" requirement.

Weakness: the hub is designed as a single-process, in-memory registry (the report's own precedent, echo's DashMap-based hub) with no cross-process fan-out mechanism described or even acknowledged as a future need.
Contrast this with the rate limiter in `realtime-sync.md`, which is explicitly "an injectable interface so the official hosted instance can swap in a shared-store implementation only if and when it scales past one process," and with `database.md`, which flags "whether the official instance needs more than one application-server process for v1" as an open question requiring a snowflake node-id range "decided before launch, not retrofitted."
`backend.md` owns the module in question and raises neither the question nor the interface seam the other two reports both considered necessary.

Failure mode: the official hosted service, which the brief requires as a real deployment target (not just self-hosted), grows past what one process can hold in connection state.
A user's two devices land on different app-server instances behind a load balancer; a message sent from a client attached to instance A never reaches that user's device connected to instance B, because there is no pub/sub or shared session backplane in the design, and nothing in `backend.md` signals this was even considered.

Resolution: add a decision or open question to `backend.md` about single- versus multi-process topology for the official server, matching the treatment the rate limiter and the ID scheme both received elsewhere.
Design `hub.rs` behind an interface that can later be backed by a shared fan-out mechanism (Postgres LISTEN/NOTIFY or Redis pub/sub), even if v1 ships single-process only.

### 4. The moderation "open question" was already answered by a sibling report, and the design is under-scoped as a result

Target: moderation/ module scope and the first "Open questions" bullet in backend.md section 4 and the closing section.

Weakness: `backend.md` presents the encryption-versus-moderation tension as unresolved, and scopes moderation defensively around that uncertainty: "if messages are end-to-end encrypted, the server cannot inspect content, so reports carry a reporter-supplied plaintext excerpt."
But `security.md`, in the same docs folder and explicitly in scope per `backend.md`'s own stated scope line, already settled this for v1: "strong transport encryption... is the mandatory v1 baseline; end-to-end encryption is explicitly deferred, not adopted."
`database.md` builds its schema on that same settled verdict, with a plaintext `messages.content` column and a generated `tsvector` GIN index for full-text search.

Failure mode: because `backend.md` treats the question as open, the moderation/ module is scoped to report-driven and behavioral signals only, even though v1 message content is, by the project's own already-settled design, server-visible plaintext.
Straightforward, implementable moderation capability (keyword and heuristic content flagging on plaintext messages) is left out of a plan for a feature the brief explicitly asks to be "excellent," not because it is technically infeasible, but because the specialist did not reconcile with a sibling report that answers the exact question raised.

Resolution: update moderation/ scope to include plaintext-content-aware automated moderation for v1 non-encrypted channels, matching the encryption verdict `security.md` and `database.md` already committed to, and remove the stale open question or replace it with a forward-looking one about moderation once opt-in E2EE DMs eventually ship.

### 5. The two-language, soon three-language strategy is accepted without weighing its recurring cost

Target: overall language and framework strategy (backend.md section 1), Rust for the main server plus Go for the relay, alongside the already-committed Dart/Flutter client.

Weakness: the report accepts "running two languages across the project doubles toolchains and CI pipelines" as a one-sentence risk, without weighing it against the brief's own explicit priority ordering, which deprioritizes development cost in favor of quality, simplicity, and long-term maintainability, and explicitly wants the project "easy to contribute to."
The rejection of "Rust for uniformity" is a single sentence calling it "unnecessary weight for a deliberately dumb, stateless forwarder," which addresses only the one-time cost of a rewrite, not the recurring cost of maintaining a second ecosystem forever.

Failure mode: every future contributor, every dependency-security cycle (`cargo-audit`/`cargo-deny` for Rust, `govulncheck`/`OSV-Scanner` for Go, `pub audit` for Dart), and every language-version bump now spans three independent ecosystems for a project whose relay component is, by the brief's own description, "intentionally minimal."
This is a cost that compounds every year the project is maintained, unlike the one-time development-time savings the report weighs it against, and it cuts directly against the brief's own stated priority ordering more than the report's treatment suggests.

Resolution: at minimum, state the recurring (not one-time) cost of the second ecosystem explicitly in the report, and give a real comparison against a minimal-dependency Rust relay (for example `hyper` plus `rustls`, no `Axum`) as an alternative that keeps the whole project to one language end to end, even if the conclusion stays the same.

## Minor findings

### 6. Idle RSS target is internally inconsistent across sibling reports

Target: backend.md section 5, "Server process idle RSS: under 30 MB," against realtime-sync.md's "an idle self-hosted gateway process... should stay well under 50MB RSS," for what is the same process.

Weakness: two sibling reports state two different numeric targets for the same idle metric on the same component, unreconciled, with no note explaining which is authoritative.

Failure mode: whichever number lands in a README or a CI resource-budget gate first becomes the de facto contract.
If the real measured figure lands at, say, 35 MB, one document's stated target is already broken on day one with nothing in either report flagging the discrepancy.

Resolution: pick one number, state it once in the report that owns resource targets, and have the other report reference it instead of restating an independently chosen figure.

### 7. The idle RSS target is never reconciled with the musl static-build choice

Target: backend.md's under-30 MB idle RSS target (section 5) against devops.md's musl-target, distroless-static Dockerfile.

Weakness: musl's allocator is well known to fragment and underperform glibc's for the many small, short-lived allocations typical of an async Tokio workload, which is exactly why some latency- and memory-sensitive Rust services deliberately swap in `jemalloc` or `mimalloc` on musl targets, itself adding a dependency and its own baseline footprint.
Neither report accounts for this interaction.

Failure mode: the 30 MB figure gets validated, if it ever is, against a glibc development build rather than the actual musl-linked release binary, and the real deployed artifact misses the target, discovered only after a CI resource-budget gate has already been written around the wrong number.

Resolution: benchmark idle RSS against the actual musl-linked release binary from day one, and decide the default allocator (system musl malloc versus `mimalloc`) explicitly as part of the resource-target section rather than leaving it implicit.

### 8. SQLx's build-time requirement is a real contributor-onboarding cost that goes unaddressed

Target: backend.md sections 1 and 6, SQLx compile-time query checking as the headline reason for choosing Rust, and the testing-strategy section's silence on offline-mode caching.

Weakness: SQLx's compile-time query verification requires either a live `DATABASE_URL` at `cargo build` time or a committed `.sqlx` offline query cache kept in sync with every migration.
The report never states which mode the project uses, or how offline-cache drift against a changed schema would be caught.

Failure mode: a new contributor clones the repository and runs `cargo build` with no local Postgres running, and gets an opaque compile error unrelated to whatever they changed, working against the brief's "easy to contribute to" goal.
Alternatively, the offline cache goes stale after a migration lands without a corresponding cache update, and CI passes against a schema snapshot that no longer matches the real database, quietly undermining the exact safety property, catching query-shape bugs like echo's JSONB `i32`/`i64` decode issue at compile time, that justified choosing Rust and SQLx over Go in the first place.

Resolution: state explicitly that `.sqlx` offline mode is committed to the repository and verified in CI with `cargo sqlx prepare --check`, add that check to the testing-strategy section, and document the local-Postgres-for-dev tradeoff for contributors in onboarding docs.

### 9. The second "open question" was also already answered by a sibling report

Target: backend.md's closing "Open questions" bullet 2, on Apple guideline scrutiny of invite-only account creation.

Weakness: `security.md`'s "Invite model and Apple guidelines" section already answers this in concrete terms: in-app reporting of messages and users (Guideline 1.2), user blocking, an acceptable-use agreement at signup, in-app account deletion (Guideline 5.1.1), a 17+ age rating, and a note that Sign in with Apple is not triggered because accounts are first-party.

Failure mode: an implementer reading `backend.md` alone would treat App Store compliance as unresolved, and could under-scope client work, for example skipping the in-app account-deletion flow, or duplicate research `security.md` already completed.

Resolution: replace the open question with a pointer to `security.md`'s verdict, or fold its concrete requirement list directly into `backend.md`'s admin/ or account-model scope so the requirement is visible wherever the account model is discussed.

## Closing note

Two of the report's central architectural choices, the ordering mechanism and the auth token model, are stale relative to decisions made elsewhere in the same document set, and both are the kind of foundational choice that is expensive to change once code exists.
Neither failure is a flaw in the reasoning inside `backend.md` taken in isolation, both read as internally coherent, well-justified decisions on their own.
The failure is coordination: this report needed to be read against `realtime-sync.md`, `database.md`, and `security.md` before being finalized, the way `database.md` explicitly did the work of reconciling with its siblings and flagging every divergence by name.
`backend.md` does not do that, and the result is a plan that would, if implemented literally, rebuild two bugs the rest of the project has already designed away.
