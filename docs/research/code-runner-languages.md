<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# Which languages a code runner can actually carry, and which of them share anything

Researched 2026-09-16, for [decision 0026](../decisions/0026-polyglot-code-runner.md).

The owner's ask was to "create sort of packs of languages, so ones that can run together get packed into the same module for free" and to sort the top twenty into buckets.
The short answer is that the packs are mostly smaller than they look, and a different split matters more than the one the question assumes.

## The two findings that change the design

**Nobody runs a WebAssembly-hosted compiler in production, for any compiled language.**
Piston, Judge0 and Riju all bake a real native compiler into the sandbox image and shell out to it.
This was read out of Piston's own build scripts, which compile GCC 10.2.0 from source at package-build time, then run `gcc -std=c11 *.c -lm` and execute the resulting binary.
The WebAssembly alternatives are real but are demos: `wapm-packages/clang` has not been pushed since July 2021, and `binji/wasm-clang` calls itself "alpha demoware" and last changed December 2023.
Rust's own self-hosting-to-WebAssembly issue has sat dormant since 2019.

**So the split that matters is not which languages share a runtime. It is interpreted against compiled.**

- An interpreted language ships one artifact that takes source and runs it. Python, Ruby, PHP, Lua, JavaScript and R all have maintained ones.
- A compiled language needs a toolchain that runs natively, outside any sandbox, before anything executes. That is a different architecture with a different security surface, and it is the architecture every existing system chose because there is no other.

A runner that hosts interpreters is a much smaller thing than a runner that compiles.
It is worth deciding which one is being built before deciding which languages go in it.

## What a WebAssembly sandbox gives, and what it does not

| Threat | Free from the sandbox? |
| --- | --- |
| Memory exhaustion | Yes. Linear memory is a hard ceiling by construction. |
| Filesystem writes, one run contaminating the next | Yes. No ambient access without an explicit capability grant. |
| Network egress | Yes. No socket capability unless the host hands one over. |
| Process exhaustion, fork bombs | Sidestepped rather than defended. A module cannot spawn processes, which holds only while the host never grants a spawn capability. |
| **Infinite loops and wall-clock time** | **No.** Nothing self-terminates. |

The last row is the one to plan around.
Every system surveyed had to add an external timeout: Piston's `run_timeout`, Judge0's `WALL_TIME_LIMIT`, Compiler Explorer's flat twenty seconds under nsjail.
slim-m's in-process module runtime already meters fuel through wasmi, so the mechanism exists in the codebase; a separate runner would need its own.

## The cautionary tale is specific, and it is not about the sandbox

Judge0's 2024 chain reached CVSS 10.0 across three CVEs, fixed in 1.13.1 on 2024-04-18.
The core sandbox held.
What failed was everything beside it: default-on network access let sandboxed code reach the internal database, weak credentials let it rewrite its own sandbox configuration, and a symlink gap turned that into command injection as root outside the sandbox.
Compiler Explorer hit a comparable escape, where malicious CMake rules symlinked build output over `/etc/passwd`, fixed by mounting everything `nosymfollow`.

Both failures were in adjacent steps that sat outside the trust boundary people thought they had drawn.
That is the argument for 0026's rule that the server brokers and the runner gets no capability to write messages: the blast radius of a compromised runner should be the answer it returns, and nothing else.

## How the existing systems package languages

| System | Isolation | Packaging | Limits |
| --- | --- | --- | --- |
| Piston | `isolate` inside Docker | One server, languages installed on demand from a package index | 3s run, 10s compile, 64 processes, 64 open files, stdout truncated at 1024 chars |
| Judge0 | `isolate`, historically privileged | One install, one shared image for many languages | 5s CPU, 10s wall, 128 MB, network off by default after the CVEs |
| Riju | A setuid binary talks to Docker, fresh container per run | **One image per language**, which is how it reaches 200+ | Not published |
| Compiler Explorer | `nsjail`, separate configs for compile and execute | One service, 81 languages, compilers as squashfs | Flat 20s wall clock |

Riju is the interesting one for this question: reaching many languages pushed it to one image per language, the opposite of packing them together.

## The buckets

Genuine sharing is rarer than the question assumes.
"Free" here means adding the second language costs approximately nothing beyond the first.

| Bucket | Languages | Shared artifact | Second language costs |
| --- | --- | --- | --- |
| .NET | C#, F# | Mono/.NET WebAssembly runtime, 2-10 MB | **Closest to free.** Both compilers are themselves managed code, so the same runtime can host them. F# adds a managed assembly, not a native toolchain. |
| C family | C, C++ | One clang frontend and sysroot | **A compiler flag**, genuinely. But clang runs natively; no maintained WebAssembly-hosted build exists. |
| JVM | Java, Kotlin, Scala | Bytecode execution via TeaVM or CheerpJ | **Free to execute, not to compile.** Running bytecode costs nothing extra. Producing it needs kotlinc or scalac, full native JVM toolchains. |
| JavaScript family | JavaScript, TypeScript | A QuickJS-class engine, 1-3 MB | **Not free.** TypeScript needs a transpile step. Type stripping is cheap but silently discards type errors, which is the wrong behaviour for a code runner. |
| Everything else | Python, Ruby, PHP, Lua, R, Dart, Swift, Rust, Go, Zig | None | Buckets of one. |

So there are two real packs, one half-pack, and a long tail of singletons.

### The interpreted singletons, all verified maintained

| Language | Artifact | Size | Last release |
| --- | --- | --- | --- |
| Lua | wasmoon | under 1 MB | 2026-09-07 |
| JavaScript | Javy, QuickJS class | 1-3 MB | 2026-05-21 |
| Python | Pyodide | ~7 MB core, 10-11 MB with numpy | 2026-08-17 |
| Ruby | ruby.wasm | 15-20 MB | nightly |
| R | webR | 20-30 MB | 2026-05-19 |
| PHP | php-wasm | 30-40 MB | 2026-09-15 |

Lua is the cheapest interpreter in the set by an order of magnitude, which matters if the first question is whether the mechanism works at all.

## Out of reach, or not evidenced

- **A compiler hosted in WebAssembly** for C, C++, Rust, Go or Zig. The attempts are abandoned.
- **Objective-C.** Shares clang's frontend in principle, but no maintained WebAssembly port of the runtime was found.
- **Swift.** Reachable but the least stable foundation here: no stable release has ever been cut, only dated snapshots, and current experimental configurations document link failures in Foundation.
- **Bash.** High chat relevance, and builds exist, but no canonical maintained one with a verifiable release date was confirmed. Worth a second look rather than an assumption.
- **SQL.** Not executable without a database behind it.
- **Visual Basic, VBA, MATLAB, PowerShell, COBOL, Ada, Fortran, Delphi, Perl.** Present in the indices, no maintained WebAssembly story found.

## A note on the index data

Four indices were cross-checked: TIOBE September 2026, PYPL from its own published dataset, the Stack Overflow survey published 2025-12-29, and GitHub's Octoverse.
They disagree sharply, and the disagreement is itself informative.

TIOBE is the outlier: it puts Visual Basic at 7, Fortran at 11, Delphi at 13 and COBOL at 20, while TypeScript sits at 39 and Kotlin at 26.
It counts search-engine hits, which rewards legacy and academic terms over what people write.
Octoverse and the Stack Overflow survey agree with each other and with intuition.

The list here is weighted toward what gets pasted into a chat message rather than raw index position, which is a judgement rather than a measurement, and is flagged as one.
