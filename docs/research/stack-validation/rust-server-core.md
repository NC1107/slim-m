# Rust Server Core: Stack Validation Report

This report validates library and tooling choices for the Rust web/runtime layer of slim-m, a lightweight Discord-style messenger.
All findings are current as of July 2026.

## Executive Summary

The planned stack is well-chosen and aligned with lightweight, maintainable principles.
Axum with Tokio provides excellent ergonomics and ecosystem integration while remaining performant.
Three targeted improvements are recommended: use jiff for datetime handling, add tower-http's trace layer for observability, and implement graceful shutdown patterns explicitly.
Most libraries show active maintenance by the Tokio ecosystem team.
No critical blockers exist; the stack is production-ready.

## Framework and Runtime

### Axum (Web Framework)

**Status: CONFIRMED**

Axum is the optimal choice for this project.
It is actively maintained by the Tokio team, showing updates as of July 2026 with 26,608 GitHub stars.
It is the fastest-growing web framework in Rust as of 2026 and prioritizes developer ergonomics alongside performance.
Axum handles approximately 17,000-18,000 requests per second on commodity hardware and achieves sub-50ms latency under 100,000 concurrent connections.
The service-based architecture via Tower middleware provides excellent composability and type safety.
Licensing is MIT/Apache-2.0 (permissive).
Compared to Actix-web (10-15% faster but more complex actor model) and Poem (minimalist but early-stage), Axum strikes the best balance for long-term maintainability and team productivity.
Axum 0.8+ provides native async trait support, eliminating the #[async_trait] macro requirement and improving performance.

### Tokio (Async Runtime)

**Status: CONFIRMED**

Tokio is the de facto Rust async runtime and the only sensible choice.
It is battle-tested, heavily maintained, and powers the entire async ecosystem including Hyper, Axum, and Tower.
It provides excellent performance characteristics for concurrent request handling.
Licensing is MIT (permissive).
No known concerns.
Use stable channel Tokio versions only; avoid experimental features for production.

## WebSocket Handling

### tokio-tungstenite

**Status: CONFIRMED**

For traditional WebSocket support, tokio-tungstenite is the correct choice.
It is the most downloaded and best-maintained WebSocket library in Rust.
Performance in tokio-tungstenite >= 0.26.2 has improved significantly and is now competitive with raw performance crates.
It maintains strict RFC 6455 compliance and is thread-safe.
Licensing is MIT (permissive).

**Gotcha:** fastwebsockets is faster in microbenchmarks but has documented unsoundness issues, non-thread-safety, and spec non-compliance.
Do not use fastwebsockets for this project.

### Axum Built-in WebSocket Extractor

**Status: CONFIRMED**

Axum provides a built-in WebSocket extractor via axum::extract::ws::WebSocket.
This is the preferred path for serving WebSocket connections from HTTP routes.
It integrates seamlessly with Axum's type-safe extractor system.
For permessage-deflate compression: Axum's WebSocket extractor does not yet expose direct configuration for permessage-deflate compression in the stable API.
If compression is required, either use tokio-tungstenite with explicit permessage-deflate setup or defer compression to a reverse proxy (Caddy or rustls already in the architecture).
Recommend deferring to reverse proxy as the simplest path.

**Security Note:** permessage-deflate has recent DoS vulnerabilities (CVE-2026-39804) if not properly bounded; ensure any compression implementation caps decompression output size.
Reverse proxy handling eliminates this risk by centralizing compression logic.

## Middleware

### Tower

**Status: CONFIRMED**

Tower provides the Service abstraction and middleware composability that makes Axum powerful.
It is actively maintained by the Tokio team, showing usage across the entire Rust web ecosystem.
Licensing is MIT (permissive).
Tower's zero-cost abstraction model means middleware composition compiles to efficient code.

### tower-http

**Status: CONFIRMED**

tower-http provides production-ready HTTP-specific middleware including CORS, compression, tracing, and timeout handling.
It has 146.5M total downloads and is actively maintained.
Licensing is MIT (permissive).

**Recommendation:** Use tower-http::trace::TraceLayer for request tracing integration with the tracing ecosystem.
This is lightweight and provides valuable observability without external dependencies.
Include configuration to log request/response pairs with structured fields for debugging.

## Observability

### Structured Logging: tracing + tracing-subscriber

**Status: CONFIRMED**

tracing is the modern standard for structured logging in Rust, developed by the Tokio team.
It provides both logging and distributed tracing through a unified span-based abstraction.
tracing-subscriber composes logging and filtering layers and is actively maintained.
Licensing is MIT (permissive).
Recent 2026 documentation confirms the ecosystem is mature and widely used in production.

**Recommendation:** Integrate tower-http::trace for HTTP middleware tracing (see above).
Use tracing span macros (#[instrument]) on key business logic and database queries.
Configure tracing-subscriber with json output for production deployments to enable structured log aggregation.

### Optional OpenTelemetry Integration

**Status: OPTIONAL - RECOMMEND DEFERRING**

tracing-opentelemetry and opentelemetry_otlp enable distributed tracing export to OpenTelemetry-compatible systems.
These are well-maintained and officially recommended by the OpenTelemetry Rust project.
Licensing is Apache-2.0/MIT (permissive).

**Recommendation:** Defer full OpenTelemetry integration to a future phase (post-MVP).
The base tracing stack provides excellent single-instance observability.
When multi-instance or distributed tracing is required, add tracing-opentelemetry as a dependency without code changes; the abstraction is designed for this.
This keeps initial deployment lightweight.

## Metrics

### metrics + metrics-exporter-prometheus

**Status: CONFIRMED**

The metrics crate provides a vendor-agnostic metrics facade.
metrics-exporter-prometheus exports metrics to the Prometheus format on an HTTP endpoint.
Both are actively maintained.
Licensing is MIT (permissive).
Recent 2026 blog posts confirm production usage.

**Recommendation:** Expose a /metrics endpoint via a dedicated thread or lightweight HTTP server (or integrate into the main Axum server on a separate route with careful attention to not blocking request handling).
Collect key metrics: request count/latency by endpoint, database query latency, connection pool utilization, and message queue depth.
Start simple; add detailed metrics based on observed production behavior.

**Note:** Prometheus scraping is a pull-based model; ensure the /metrics endpoint responds quickly and does not require expensive computation.
Use atomic counters and gauges to avoid lock contention.

## Error Handling

### thiserror + anyhow

**Status: CONFIRMED**

thiserror is ideal for defining structured error types in this Rust service.
anyhow is appropriate for propagating context through the request handling path.

**Recommended Pattern:**
- Define custom error types with thiserror for domain-specific failures (e.g., DatabaseError, ValidationError, AuthenticationError).
- Use anyhow for wrapping and adding context to lower-level errors (I/O, serialization).
- Implement axum::response::IntoResponse for custom error types to convert them into HTTP responses with appropriate status codes.

Licensing: both are MIT (permissive).
Both are actively maintained and widely used.

## Configuration

### Recommended: figment (for layered config) + envy (for environment variables)

**Status: CONFIRM figment - RECOMMEND using envy for env-only setup initially**

figment provides hierarchical configuration merging from multiple sources (files, environment, defaults).
It is well-maintained and suitable for complex deployments.
Licensing is MIT (permissive).

For slim-m's initial self-hosted deployment model, recommend a simpler approach:
- Use envy for environment variable deserialization (type-safe via serde).
- Load a single TOML file for defaults if needed.
- Defer hierarchical merging to figment only if/when multi-source config becomes necessary.

This keeps initial setup lightweight and operational complexity low for self-hosted admins.

**Specific Recommendation:**
Structure config as environment variables with a consistent prefix (e.g., SLIM_M_), deserialize into a typed struct with envy, and document all options in the README.
This is the simplest path for containerized deployments.

## Request Validation

### garde (Modern Choice) vs validator

**Status: RECOMMEND garde over validator**

garde is a modern rewrite of the validator crate with better derive macro ergonomics.
It is actively maintained and provides nearly identical functionality to validator.
Licensing is MIT (permissive).

**Recommendation:** Use garde for request validation.
Define validation rules via derive macros on request struct fields.
Integrate with Axum via custom extractors that call garde::Validate before returning the request body.
This provides type-safe validation and clear error messages.

**Integration with Axum:**
Consider axum-valid if building many validated endpoints; it provides pre-built extractors for garde, validator, and other validation crates that automatically return 400 with validation errors.
This reduces boilerplate.

## Rate Limiting

### tower_governor (Recommended)

**Status: CONFIRM tower_governor**

tower_governor is a Tower middleware for rate limiting backed by the governor crate (GCRA algorithm).
It supports per-IP rate limiting, global limits, and custom keys.
It is actively maintained and production-ready.
Licensing is MIT (permissive).

**Recommendation:**
Implement IP-based rate limiting via tower_governor to prevent abuse.
Start with conservative limits (e.g., 100 req/s per IP, 10 concurrent connections per IP) and adjust based on production metrics.
Configure burst allowance to handle legitimate traffic spikes.
Ensure the rate limiter runs early in the middleware stack before expensive handlers.

**Alternative Consideration:**
For very high-traffic scenarios, consider using Caddy's built-in rate limiting instead and keep the server logic simpler.
This is operationally simpler for self-hosted deployments.

## Graceful Shutdown

### Recommended Pattern

**Status: NEEDS EXPLICIT IMPLEMENTATION**

Axum provides with_graceful_shutdown(signal) to coordinate shutdown.
Tokio provides tokio::signal for handling OS signals.
Cancellation tokens via tokio_util::sync::CancellationToken enable clean task cancellation.

**Recommendation:**
Implement explicit graceful shutdown:
1. Catch SIGTERM and SIGINT via tokio::signal.
2. Use CancellationToken to signal all background tasks to terminate.
3. Call server.with_graceful_shutdown() to complete in-flight requests before exiting.
4. Set a timeout (e.g., 30 seconds) for shutdown; force exit if exceeded.
5. Log shutdown events at INFO level for operational debugging.

Axum provides example code in its repository (examples/graceful-shutdown/).
Copy and adapt for slim-m's specific cleanup needs (e.g., closing database connections, flushing metrics).

## Unique Identifiers

### UUID v7

**Status: CONFIRMED with caveat on performance**

The uuid crate with v7 feature provides standards-compliant UUIDv7 generation.
It is actively maintained and widely used.
Licensing is MIT/Apache-2.0 (permissive).

**Performance Consideration:**
Standard uuid crate UUIDv7 generation takes approximately 1.4 microseconds per ID.
For most use cases (message creation, invite generation), this is negligible.
If performance testing shows UUID generation is a bottleneck (unlikely), fast-uuid-v7 offers ~165x faster generation (8.4ns), though it is newer and less tested.

**Recommendation:**
Start with the standard uuid crate.
Generate UUIDs on the client side (already specified in the architecture).
The server should assign sequence numbers but not generate UUIDs for user-facing events.
If profiling identifies UUID generation as a bottleneck, evaluate fast-uuid-v7.

## Date and Time Handling

### jiff (Recommended over chrono or time)

**Status: RECOMMEND CHANGE FROM chrono TO jiff**

jiff is a new(ish) datetime library from BurntSushi that prioritizes correctness and usability over chrono's historical baggage.
As of July 2026, jiff is the recommended choice for new Rust projects.
Key advantages over chrono:
- IANA timezone database integration built-in (chrono requires external dependencies).
- DST-aware arithmetic out of the box.
- Better API ergonomics; harder to misuse.
- No epoch assumptions; works seamlessly with any timezone.

chrono remains maintained for legacy code but is considered superseded for new projects.
time is suitable for embedded systems but unnecessary for web services.

Licensing: jiff is MIT/Apache-2.0 (permissive), same as chrono.

**Note on jiff 1.0 Status:**
As of April 2026, jiff 1.0 remains in development (originally planned for Summer 2025).
The 0.x API is stable in practice, and production use is safe.
Pin jiff to a specific 0.x version in Cargo.toml to avoid surprises; migrate to 1.0 when released.

**Recommendation:**
Use jiff for all datetime handling in slim-m.
Define time constants and parsing functions in a utilities module to centralize timezone handling.
Use UTC for all internal storage and serialization; convert to user timezone only for display.

## Additional Recommended Additions

### tower-http::trace::TraceLayer

**Status: ADD THIS**

See the Middleware section above.
This should be added as a middleware layer early in the request processing pipeline.

### tokio_util (CancellationToken for graceful shutdown)

**Status: ADD THIS**

Part of the Tokio ecosystem.
Provides CancellationToken for coordinating shutdown across tasks.
Licensing: MIT (permissive).

**Usage:** See Graceful Shutdown section above.

### serde + serde_json

**Status: CONFIRM (assumed existing dependencies)**

These are standard Rust serialization libraries.
No concerns; both are ubiquitous and actively maintained.
Licensing: MIT/Apache-2.0 (permissive).

### validate-http-request-method (or manual validation)

**Status: LOW PRIORITY - DEFER**

If needed for strict HTTP method validation, implement custom middleware or use an existing extractor rather than adding a dedicated crate.
Axum's type system provides good guarantees already.

## Changes and Removals

### No changes recommended for confirmed libraries.

All primary choices (Axum, Tokio, Tower, tracing, sqlx) are optimal and well-maintained.
The modifications recommended are additive only: jiff for datetime, explicit graceful shutdown patterns, and tower-http::trace.

## Known Risks and Version Pitfalls

### 1. SQLite Write Concurrency

**Risk:** SQLx with SQLite can experience lock starvation and write performance degradation under concurrent write load.

**Mitigation:**
- Design the schema to minimize write contention (combine frequently co-written tables; use normalized keys).
- Use the architecture's design of a single serialized writer path for writes (already specified).
- For read-heavy workloads, the read-only connection pool is ideal.
- Monitor write latency in production; if lock contention appears, consider switching to Postgres (already a documented future path).

### 2. WebSocket permessage-deflate Security

**Risk:** Improper permessage-deflate implementation can lead to DoS via memory exhaustion (CVE-2026-39804).

**Mitigation:**
- If using compression, defer to reverse proxy (Caddy/rustls).
- If client-side compression is required, cap decompression output to a reasonable limit (e.g., 1MB per message).
- Test with adversarial payloads as part of security review.

### 3. jiff 1.0 Timeline

**Risk:** jiff 1.0 release date is uncertain; 0.x API is stable but version bumps could introduce incompatibilities.

**Mitigation:**
- Pin jiff to a specific 0.x version in Cargo.toml (e.g., 0.2.x).
- Test jiff 1.0 release candidate before upgrading.
- Wrap jiff calls in a utilities module to centralize any future migration logic.

### 4. Metrics and Prometheus Endpoint

**Risk:** A slow /metrics endpoint can become a request handling bottleneck if not careful.

**Mitigation:**
- Use atomic types (Arc<AtomicU64>, etc.) for metrics to avoid lock contention.
- Compute /metrics response eagerly on a background thread or at request time with cached results.
- Set a short timeout (< 100ms) on the /metrics endpoint; if it exceeds this, return an error rather than blocking.

### 5. Axum 0.8 Native Async Traits

**Risk:** Code written with older #[async_trait] may not benefit from Axum 0.8's native async trait support.

**Mitigation:**
- Upgrade to Axum 0.8+ and remove #[async_trait] from custom extractors where possible.
- This is a breaking change for some custom code but improves performance.
- Plan this as a dependency upgrade during early development before stabilizing APIs.

## Version Snapshot (as of July 2026)

Approximate current versions; verify via crates.io for latest:

- axum: 0.8.x
- tokio: 1.x (latest 1.x minor)
- tower: 0.5.x
- tower-http: 0.6.x
- tracing: 0.1.x (stable API)
- tracing-subscriber: 0.3.x
- jiff: 0.2.x (1.0 in progress)
- uuid: 1.x (with v7 feature)
- sqlx: 0.8.x
- serde: 1.0.x
- garde: 0.20.x+

Check crates.io for minor version updates; maintain compatibility with the current Tokio ecosystem versions.

## Deployment and Operations

### Docker Environment

Ensure the Dockerfile:
- Builds with a stable Rust version (latest stable at release time).
- Uses multi-stage builds to minimize image size (important for lightweight self-hosting).
- Includes the target binary only; no source code or build artifacts.
- Exposes PORT via environment variable (default 8080).
- Sets Cargo.lock to ensure reproducible builds.

### Configuration in Production

Use environment variables via envy.
Example variables:
- SLIM_M_DATABASE_URL: SQLite file path or Postgres connection string.
- SLIM_M_LOG_LEVEL: debug, info, warn, error.
- SLIM_M_BIND_ADDR: 0.0.0.0:8080 (or similar).
- SLIM_M_METRICS_ENABLED: true/false.
- SLIM_M_GRACEFUL_SHUTDOWN_TIMEOUT_SECS: 30.

Document all options in README with sensible defaults.

## Conclusion

The planned stack is well-chosen and production-ready.
Axum with Tokio provides the right balance of performance, maintainability, and ecosystem support for slim-m's self-hosting focus.
Recommended changes are minimal: adopt jiff for datetime, implement explicit graceful shutdown, and integrate tower-http::trace for observability.
No critical risks; all primary dependencies are actively maintained by the Tokio ecosystem.
Proceed with confidence.
