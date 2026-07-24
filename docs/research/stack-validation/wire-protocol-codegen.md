# Wire Protocol and Codegen Stack Validation

Status: Due-diligence pass, 2026-07-23.

This document validates the schema-first wire protocol and code-generation toolchain for slim-m's control plane.
The architecture decision document decides JSON over HTTP and WebSocket with schema-first generation from one source of record, compile-time-checked queries, and additive-only versioning.
This pass examines whether the exact libraries and tools named to implement that decision are the right choices now, given their 2026 status, maintenance, performance, licensing, and long-term maintainability fit for a lightweight, self-hosted messaging platform.

Scope: The schema-first toolchain validating and generating code for the REST and WebSocket control plane (text messages, presence, signaling, accounts, channels, invites, admin operations).
Out of scope: The Voice Canvas high-frequency stream (voice, screen share, canvas operations) will use a separate codec optimized for latency and bandwidth.

## Validation Summary

### Rust side: OpenAPI generation and type checking

#### utoipa (OpenAPI generation from Axum handlers)

- Status: **CONFIRMED**
- Maturity: Production-ready, actively maintained.
- Current version: 0.30+ (dual-licensed Apache 2.0 / MIT).
- Maintenance: 858+ commits, active PR queue, regular releases.
- Why it wins: Code-first macro-driven generation directly from Axum handlers and types, with `utoipa-axum` bindings for seamless integration.
Handles generic types, recursive schema collection, OpenAPI 3.1 support.
`axum_extras` feature allows parameter extraction without boilerplate.
Dual licensing and Tower/Tokio ecosystem alignment mean no divergence risk.
- Gotchas: Macro-based codegen requires careful attribute annotation, and changes to handler signatures can require schema re-declaration.
OpenAPI documentation quality depends on thorough type annotations; under-annotated handlers produce incomplete docs.
- Recommendation: CONFIRMED as primary choice.
Utoipa is the de-facto standard for Axum OpenAPI in 2026, with a stable, well-integrated codegen story.
Use the `utoipa-axum` bindings explicitly and the `swagger-ui` or `redoc` feature for documentation UI.
Consider `utoipa-scalar` if a more modern, faster schema UI is needed (minimalist alternative to Swagger UI).

#### Aide (code-first OpenAPI for Axum)

- Status: ALTERNATIVE, not recommended for primary path.
- Maturity: Actively maintained, 663 stars, 318 commits.
- Current version: Recent, dual-licensed MIT / Apache 2.0.
- Why it exists: Doc-comment-driven generation (rovo builds on aide for annotated OpenAPI).
- Gotcha: Aide is lower-level and requires additional setup; the ecosystem builds on top of it rather than using it directly.
Manual comment annotations required for doc-comment-driven workflow.
- Recommendation: SKIP for primary generation.
Utoipa provides smoother Axum integration with less manual annotation burden.
Aide is useful only if a doc-comment-driven workflow is preferred, which conflicts with the macro-centric Rust style; not the right fit for this stack.

#### Okapi (alternative OpenAPI generator)

- Status: NOT VALIDATED (insufficient 2026 data).
- Recommendation: SKIP.
Okapi is not actively developed as a modern alternative; utoipa has become the clear standard in the ecosystem.

#### Schemars (JSON Schema generation from Rust types)

- Status: **CONFIRMED** for WebSocket envelope and message schemas.
- Maturity: Production-ready, actively maintained.
- Current version: 1.2.1+ (released June 22, 2026).
- Maintenance: Regular releases, GitHub Actions CI, comprehensive test coverage.
- License: MIT.
- Why it wins: `#[derive(JsonSchema)]` macro generates JSON schemas that match serde serialization exactly.
Respects `#[serde(...)]` attributes, ensuring generated schemas are faithful to actual wire encoding.
Integration with serde means the schema and serialization are always in sync.
- Gotchas: Schema generation quality depends on complete type annotations; generic types may require manual schema specification.
Example-based schema generation (`schema_for_value!`) produces less precise schemas than trait-based derivation.
- Recommendation: CONFIRMED.
Use schemars for generating JSON schemas from Rust WebSocket message types, ensuring the schema always matches the actual serialized format.
Pair with serde to keep serialization and schema validation synchronized.

#### Typify (Rust type generation from JSON Schema)

- Status: **CONFIRMED** for bidirectional schema-first workflow.
- Maturity: Production-ready, maintained by Oxide Computer.
- Current version: Recent, Apache 2.0 license.
- Features: Generates Rust types from JSON Schema documents via macro or build script.
Customizable derives, builder interfaces, type replacement, conversion overrides.
- Why it wins: Enables a true schema-first workflow where the JSON Schema is the source of record and Rust types are generated.
Supports both macro (`import_types!`) and build-script approaches for different use cases.
- Gotchas: Generated types depend on JSON Schema quality; complex recursive schemas can produce unwieldy generated code.
Type replacement and custom mapping add configuration complexity if needed.
- Recommendation: CONFIRMED for bidirectional use.
If the schema is the source of record, use typify to generate Rust types.
If Rust types are the source of record, use schemars to generate schemas.
For slim-m, the pattern is: define OpenAPI schema -> generate Rust types with typify -> implement handlers -> schemars validates that types match the schema.

#### Serde and Serde_json (serialization and validation)

- Status: **CONFIRMED** as foundation.
- Maturity: De-facto standard, ubiquitous in Rust ecosystem.
- Current version: 1.0+, stable API.
- Maintenance: Widely maintained, hundreds of crates depend on it.
- License: MIT + Apache 2.0.
- Why it wins: Zero-cost abstraction over JSON, battle-tested, integrates cleanly with schemars and typify.
Enables compile-time JSON validation when paired with schemars.
- Gotchas: JSON-over-the-wire means no binary efficiency; mitigated by permessage-deflate.
Default derive behavior can produce verbose generated code for large schemas.
- Recommendation: CONFIRMED.
No alternative necessary; serde is the Rust standard for serialization and is optimal for this use case.

### Dart side: Codegen from OpenAPI

#### openapi_generator_cli (wrapper around openapi-generator)

- Status: **CONFIRMED** as primary choice.
- Maturity: Actively maintained, version 7.0.0 (published 53 days ago).
- Publisher: Verified (devappliance.com).
- Quality: 160 pub points, 17.1k downloads, 20 likes.
- License: BSD-3-Clause.
- Capability: Dart wrapper around the upstream OpenAPI Generator project, supports multiple languages and generators.
Why it wins: Mature, language-agnostic upstream project with Dart-specific bindings.
Generates null-safe Dart client code from OpenAPI 3.0.x schemas.
CLI-based, integrates easily into CI/CD pipelines and build_runner workflows.
- Gotchas: Depends on the upstream openapi-generator project, which is Java-based; no pure-Dart implementation.
Generated code quality varies depending on schema clarity; poorly-structured schemas produce verbose, awkward clients.
Configuration can be verbose; custom templates may be needed for fine-tuned output.
- Recommendation: CONFIRMED.
Use openapi_generator_cli as the primary Dart client generation tool.
Integrate into CI/CD to regenerate on schema changes; fail the build if generated code differs from committed code.

#### swagger_dart_code_generator (alternative Dart generator)

- Status: **ALTERNATIVE**, viable second choice.
- Maturity: Actively maintained, version 4.1.1 (published 7 months ago).
- Quality: 331 likes, 145 pub points, 58.5k downloads, Apache 2.0 license.
- Capability: Dart-specific code generator that processes Swagger/OpenAPI specs.
Generates models, HTTP requests, converters, and enums.
Built specifically for Dart, with Chopper and JsonAnnotation integration.
- Why it exists: Dart-native alternative that avoids the Java dependency of upstream openapi-generator.
Better control over generated code style for Dart idioms.
- Gotchas: Less mature than the wrapper approach; smaller ecosystem and fewer configuration options.
Swagger/OpenAPI support may lag behind the main openapi-generator project.
- Recommendation: ALTERNATIVE.
If the Java dependency of openapi-generator becomes problematic or if Dart-native code generation is preferred, consider swagger_dart_code_generator.
For now, openapi_generator_cli is the safer choice with broader support.

#### json_serializable and freezed (complementary code generation)

- Status: **CONFIRMED** for runtime serialization and immutability.
- Maturity: Production-ready, widely adopted.
- Versions: json_serializable 6.14.0 (Google-published), freezed actively maintained.
- License: BSD-3-Clause (Google's json_serializable).
- Why they fit: After code generation from OpenAPI, freezed provides immutable data classes and freezed provides union types for tagged messages.
json_serializable handles serialization/deserialization to/from JSON at runtime.
Together they provide type-safe, immutable models with full serialization support.
- Gotchas: Requires build_runner; two-phase build process adds complexity.
Freezed union types are powerful but can generate verbose code for complex message types.
Integration between generated OpenAPI types and freezed-decorated types requires careful design.
- Recommendation: CONFIRMED as secondary layer.
Use openapi_generator_cli to generate initial Dart types from OpenAPI.
Wrap or extend generated types with freezed annotations for immutability and pattern matching if needed.
Use json_serializable only if the generated serialization from openapi_generator is insufficient.

#### json_schema (Dart runtime JSON Schema validation)

- Status: **OPTIONAL**, for runtime validation in client.
- Maturity: Platform-agnostic, actively maintained.
- Publisher: Verified (workiva.com).
- Capability: Validates JSON instances against JSON Schema at runtime.
Supports multi-version JSON Schema (up to Draft 7).
- Why it fits: Optional runtime schema validation on the client side if needed for defense-in-depth.
Useful for validating server responses before processing in critical paths.
- Gotchas: Runtime validation is CPU-bound and not suitable for every message; use only where actual correctness risk exists.
Validation errors must be handled gracefully in the client.
- Recommendation: OPTIONAL.
Add if needed for runtime response validation in critical paths (e.g., account creation, message sync).
Do not validate every message; reserve for security or consistency-critical operations.

### JSON Schema validation in CI

#### jsonschema (Rust validator)

- Status: **CONFIRMED** for Rust-side schema validation.
- Maturity: Production-ready, actively maintained.
- Current version: 0.48.5 (released July 22, 2026).
- License: MIT.
- Features: High-performance JSON Schema validation, supports Draft 4 through Draft 2020-12.
CLI available via `jsonschema` crate for use in CI.
Structured error reporting for detailed validation diagnostics.
- Why it wins: Rust-native, compile-time macro support for embedding schemas, performant.
Easy to integrate into Cargo test suite and CI pipelines.
- Recommendation: CONFIRMED for Rust CI.
Use jsonschema for validating generated OpenAPI specs and WebSocket message schemas in the Rust build.

#### ajv (JavaScript/Node.js validator)

- Status: **CONFIRMED** for CI schema drift detection.
- Maturity: Fastest JSON Schema validator, widely adopted.
- Features: Supports Draft 04-2020-12, optimized validation code generation, CLI via ajv-cli.
- Why it fits: Primary choice for CI validation of OpenAPI schemas and JSON Schema documents.
Available in CI environments without Rust; fast for large schema sets.
- Recommendation: CONFIRMED for CI scripting.
Use ajv-cli in GitHub Actions or CI scripts to validate schema changes:
```bash
ajv validate -s schema.json -d message-examples.json
```
Fail the build if schema validation fails.

#### oasdiff (OpenAPI breaking-change detection)

- Status: **CONFIRMED** for breaking-change CI enforcement.
- Maturity: Actively maintained, 1.3k stars, production-ready.
- Version: Recent, Docker and GitHub Action support.
- Features: Detects breaking changes in OpenAPI specs.
Commands: `breaking` (show only breaking changes), `changelog` (human-readable).
Hosted version at oasdiff.com, CLI and GitHub Action integration.
- Why it wins: Purpose-built for OpenAPI compatibility checking, essential for the additive-only versioning rule.
Easy CI integration; fail the build if a breaking change is introduced.
Lightweight standalone binary.
- Recommendation: **CONFIRMED as critical CI gate**.
Add oasdiff to the CI pipeline to enforce additive-only schema evolution.
Configuration: compare the current schema against the previous release tag.
Fail on any breaking change, allowing only additive fields, renamed fields with aliases, and deprecation markers.

### Wire format and WebSocket support

#### axum WebSocket support

- Status: **CONFIRMED** for connection upgrade and routing.
- Maturity: Stable, part of Tokio ecosystem.
- What it provides: `extract::ws` extractor for WebSocket upgrade, low-level message stream API.
Lifecycle management (open, read, write, close) left to the application.
- Why it fits: Framework-native integration; no additional dependencies for basic WebSocket.
Minimal boilerplate for connection upgrade from HTTP.
- Gotchas: Low-level API means the application must handle backpressure, slow clients, idle timeouts, and graceful shutdown.
No built-in permessage-deflate; compression must be handled explicitly.
Unbounded per-connection queues risk memory leaks if not carefully bounded.
- Recommendation: CONFIRMED for upgrade and routing.
Use axum's `extract::ws` for WebSocket upgrade.
Implement connection-lifecycle management (backpressure, timeouts, slow-client handling) in a dedicated module, not inline in handlers.

#### Permessage-deflate (WebSocket compression)

- Status: **FLAGGED** - support is framework-dependent, not automatic.
- Current situation: Tungstenite (underlying WebSocket library) version 0.30.0 is current, but documentation does not explicitly confirm permessage-deflate support.
- Axum's WebSocket support does not include built-in permessage-deflate middleware.
- tower-http does not provide WebSocket compression middleware.
- Recommendation: **REQUIRES EXPLICIT IMPLEMENTATION**.
Permessage-deflate is not automatic in the chosen stack; it must be enabled in tungstenite or added as a custom wrapper.
Action: Before implementation, verify tungstenite's permessage-deflate support in its source (https://github.com/snapview/tungstenite-rs).
If supported: enable it in the WebSocket connection setup.
If not supported: consider adding a custom deflate wrapper around message serialization, or use a thin binary framing layer for hot paths as the architecture document reserves.
Priority: Implement and measure permessage-deflate's impact on bandwidth and latency before deciding whether to adopt it for all messages or reserve it for high-volume paths.

#### Typed WebSocket envelope

- Status: **CONFIRMED** via serde and schemars.
- Pattern: Define a Rust enum for the message union, derive Serialize, and use schemars to generate the schema.
Each variant is a discriminated type with a type field and payload.
- Implementation: Use serde's `#[serde(tag = "type")]` attribute for the discriminator field.
Derive JsonSchema to generate the schema.
Generate Dart types from the schema using openapi_generator.
- Example (pseudo-Rust):
```rust
#[derive(Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum WsMessage {
  #[serde(rename = "text")]
  Text { content: String, seq: i64 },
  #[serde(rename = "presence")]
  Presence { user_id: Uuid, status: String, seq: i64 },
  #[serde(rename = "typing")]
  Typing { user_id: Uuid, seq: i64 },
}
```
- Recommendation: CONFIRMED.
Use serde discriminated enums for WebSocket messages.
Generate schemas with schemars.
Generate Dart clients with openapi_generator.
Add envelope-level versioning and protocol version field for forward compatibility.

## Additions: Libraries and tools to add

### 1. json_pointer (runtime validation and patching)

- Package: `jsonpointer` (Rust), `json_pointer` (Dart).
- Purpose: Runtime JSON Pointer (RFC 6901) support for selecting fields in schemas and messages during validation or patching.
- Why add it: Enables efficient partial-message updates and validation of specific fields without deserializing the entire payload.
Useful for the Voice Canvas and for patching operations if ever needed.
- Fit: Lightweight, minimal dependencies, permissively licensed.
- Priority: LOW.
Add if partial-update or patch-style operations are implemented; not required for v1.

### 2. cargo-nextest (Rust test runner)

- Package: `cargo-nextest` (installed as a Cargo plugin).
- Purpose: Faster, more parallel Rust test runner with better error reporting.
- Why add it: Performance and developer experience; tests run faster and report results more clearly.
Useful for catching flaky tests in CI.
- Fit: Zero production-code dependencies; build-time only.
- Priority: MEDIUM.
Add to the CI pipeline and local dev workflow early to catch test flakiness.

### 3. cargo-audit (security vulnerability scanning)

- Package: `cargo-audit` (Cargo plugin).
- Purpose: Scans Cargo dependencies for known security vulnerabilities.
- Why add it: Security hygiene for a messaging platform holding user data.
Lightweight, easy to integrate into CI.
- Priority: HIGH.
Add to CI as a blocking gate; fail the build on any vulnerable dependencies.

### 4. tracing and tracing-subscriber (structured logging)

- Packages: `tracing`, `tracing-subscriber` (Rust); Flutter's `logger` package (Dart).
- Purpose: Structured, context-aware logging for debugging and observability.
- Why add it: Better than println!-based debugging for a distributed realtime system.
Tracing crate is lightweight and integrates well with async code.
- Fit: Minimal overhead, integrates with OpenTelemetry for metrics.
- Priority: MEDIUM.
Add early to aid development and to support observability on self-hosted deployments.
Tracing macros (trace!, debug!, info!) provide structured events with context.

### 5. openapi-generator-go (for the push relay)

- Package: `openapi-generator` (upstream project, used via CLI).
- Purpose: Generate Go client code for the push relay service to call back to the main server.
- Why add it: Consistency across services; both server and relay use OpenAPI schemas.
- Fit: Covered by the main openapi-generator project.
- Priority: MEDIUM (relevant when the relay service is implemented).

## Changes: Recommendations for replacing current choices

### No major replacements recommended.

The schema-first stack is well-suited to slim-m's requirements.
No current choice is a poor fit that warrants replacement.
However, two areas warrant close monitoring:

#### 1. Permessage-deflate support (implicit change needed)

- Current: Axum and tungstenite do not provide automatic permessage-deflate.
- Recommendation: Before implementation, measure WebSocket message sizes and determine if permessage-deflate is necessary.
If yes, explicitly enable it in tungstenite or implement a custom wrapper.
If no, document the decision and reserve a binary encoding escape hatch for future hot paths.
- Confidence: MEDIUM.
This is not a replacement but an explicit implementation detail that must be decided during development.

#### 2. WebSocket library choice (monitoring point)

- Current: Axum + tungstenite (via axum's built-in support or axum-tungstenite wrapper).
- Alternative to monitor: hyper directly with tungstenite if Axum's overhead becomes measurable.
- Recommendation: KEEP Axum for now; it provides excellent integration and a clean API.
If profiling reveals WebSocket handling as a bottleneck, consider dropping to hyper + tungstenite directly.
For v1, Axum's ergonomics are worth more than a marginal performance gain.
- Confidence: HIGH.
Axum is the right choice now; reconsider only if profiling data supports a change.

#### 3. OpenAPI generator version tracking

- Current: openapi_generator_cli (version 7.0.0).
- Recommendation: Pin the version and review the changelog before any major bump.
OpenAPI Generator is a large upstream project; major versions may introduce breaking changes in generated code structure.
Test generated Dart code thoroughly after any upgrade.
- Confidence: HIGH.
Version stability matters for reproducible builds; set a policy of pinned versions and staged upgrades.

## Risks and version pitfalls

### Critical risks

1. **Permessage-deflate is not automatic**
   - Risk: WebSocket frames are not compressed by default, increasing bandwidth on self-hosted deployments.
   - Impact: Higher bandwidth costs for relay service and worse user experience on mobile networks.
   - Mitigation: Measure frame sizes early; implement permessage-deflate or reserve it as an escape hatch.
   - Status: Requires explicit decision and implementation during development.

2. **Schema drift between OpenAPI and generated code**
   - Risk: If CI regeneration is skipped or committed generated code is manually edited, the two sides drift silently.
   - Impact: Subtle bugs where client and server disagree on message format.
   - Mitigation: CI must regenerate both Dart and Rust types from the schema on every change and fail if any diff appears.
Use a script to detect and block commits of manually-edited generated code.
   - Status: Process-dependent; mitigated by CI discipline.

3. **JSON serialization mismatch between serde and schemars**
   - Risk: If serde attribute changes (e.g., rename, skip) are made without updating schemars, the schema becomes invalid.
   - Impact: Client deserializes correctly but schema validation fails, or vice versa.
   - Mitigation: Keep serde and schemars in the same type definition; use tests to validate that serde serialization matches the schema.
   - Status: Design-time concern; mitigated by testing discipline.

### Version pitfalls

1. **Utoipa 0.30+ to 1.0 transition**
   - Watch for: API changes in macro syntax or OpenAPI generation when utoipa reaches 1.0.
   - Mitigation: Test against release candidates; plan for potential generated schema structure changes.
   - Timeline: Not imminent in mid-2026.

2. **Tungstenite 0.30 pinning**
   - Watch for: Major version changes to tungstenite may introduce permessage-deflate or change compression behavior.
   - Mitigation: Review changelogs carefully; test with a new minor version before committing.
   - Timeline: Monitor 0.31+ releases.

3. **Serde 1.0 stability**
   - Status: Serde 1.0 is stable and unlikely to introduce breaking changes; safe for long-term pinning.
   - Mitigation: No action needed; serde is the Rust standard.

4. **OpenAPI Generator major version bumps**
   - Watch for: Version 8.0+ may introduce breaking changes in generated Dart code.
   - Mitigation: Test generated code after any upstream bump; maintain a version matrix of known-good generator versions.
   - Timeline: Monitor upstream releases quarterly.

5. **json_serializable (Dart) 7.0+ release**
   - Watch for: Null safety and code generation may change in major versions.
   - Mitigation: Google publishes long-term support; pin to a known-good version and test before upgrading.
   - Timeline: Currently at 6.14.0; no urgent upgrade needed.

### Dependency health

All recommended libraries are actively maintained (as of July 2026):
- Utoipa: 858+ commits, 163 issues, active PR queue.
- Schemars: Released June 22, 2026, recent activity.
- Typify: Maintained by Oxide Computer, stable.
- Progenitor: 1,152 commits, actively developed.
- Jsonschema: Released July 22, 2026, latest as of this assessment.
- OpenAPI Generator: Upstream project with multi-language support, mature.
- Oasdiff: 1,877 commits, 1.3k stars, production-ready.
- Serde: De-facto standard, ubiquitous ecosystem.

No libraries show signs of abandonment or maintenance decay.
License compatibility across the stack is strong: MIT, Apache 2.0, BSD-3-Clause (permissive).

## Conclusion

The schema-first JSON stack is well-chosen and the exact libraries and tools named are the right picks for 2026.
Utoipa and openapi_generator_cli form a solid Rust-to-Dart bridge with compile-time type safety on the Rust side and clean generated code on the Dart side.
Schemars and serde ensure serialization and schemas stay synchronized.
Oasdiff enforces the additive-only versioning rule in CI.
The stack is lightweight, permissively licensed, actively maintained, and well-suited to a self-hosted, long-lived messaging platform.

One gap must be addressed during implementation: permessage-deflate is not automatic and must be explicitly enabled or reserved as an escape hatch.
Measure frame sizes early and make the decision informed by data.

No major replacements are recommended.
The only changes are additions (cargo-nextest, cargo-audit, tracing) and one monitoring point (permessage-deflate implementation).
Version pinning and CI discipline are the primary defenses against drift and compatibility issues.
