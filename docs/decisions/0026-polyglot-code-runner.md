<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# 0026 - One runner service for the common languages, modules for the odd ones

Status: proposed, 2026-09-16.
Raised by the owner after finding that a python code block offered a Run button and answered with a JavaScript engine's `ReferenceError`.
Their framing: "I would rather have a generalized language container that runs in the background and handles majority of common languages and the odd ones we can split out into their own modules."

This does not reverse anything.
It is [0007](0007-extensions-and-untrusted-execution.md) being picked up, which is the one thing that record said it was waiting for.

## What is true today

`code-exec` in the addons repository embeds Boa, a JavaScript interpreter written in Rust, compiled to WebAssembly and run in the server process under the module runtime from [0021](0021-modules-and-the-dock.md).
It runs JavaScript and nothing else, and its manifest says "JavaScript first".

Nothing about that is wrong, and the in-process module runtime should keep doing what it does.
It is the right shape for a tic-tac-toe board or a dice roll: small, sandboxed, no ambient authority, cheap enough to run inside the server.

It is the wrong shape for a Python interpreter.
A language runtime is tens of megabytes before it has run a line, wants a filesystem it can believe in, and is not something to load into the address space that holds the SQLite file, the media root, the LiveKit secret and every session token.

## The decision

**Common languages get one runner service. Odd ones stay modules.**

The runner is a separate process the server speaks a defined protocol to, exactly as 0007 requires and exactly as the push relay already works.
It is absent by default, and absent is a normal state rather than a degraded one: a deployment that never adds it behaves as it does today, with no Run button for anything the in-process modules do not claim.

**Inside that service, each language is a WebAssembly runtime, not a native one. Which means interpreted languages only.**

This is the part 0007 could not have written in August, because it predates the module runtime existing.
It gives two independent boundaries rather than one: the service boundary bounds what a compromised runner can reach, which is nothing of ours, and the WebAssembly boundary bounds what one run can do to the runner, so a person who hangs a Python interpreter does not take out somebody else's Ruby.

The research in [docs/research/code-runner-languages.md](../research/code-runner-languages.md) put a hard limit on how far that reaches, and it is the finding that most shaped this record.
**No compiled language has a WebAssembly-hosted compiler in production, anywhere.**
Piston, Judge0 and Riju all bake a native compiler into the sandbox image and shell out to it, which was read out of Piston's own build scripts.
The WebAssembly attempts are abandoned: `wapm-packages/clang` last moved in 2021, `binji/wasm-clang` calls itself alpha demoware and last moved in 2023, and rustc's self-hosting issue has been dormant since 2019.

So this record covers interpreted languages and declines compiled ones.
Python, Ruby, PHP, Lua, JavaScript and R all have maintained WebAssembly interpreters, verified with release dates, and between them they cover most of what anyone pastes into a chat message.
C, C++, Rust, Go, Java and C# need a native toolchain running outside any sandbox before anything executes.
That is a different architecture with a much larger surface, it is the architecture every existing system was forced into, and it should be its own decision rather than a footnote to this one.

**The server brokers and never executes.**

Authorization, scoping and ceilings live in the server, where 0007 put them, and it should be possible to read the whole security story without reading the runner.
An invocation carries the block that triggered it and nothing else.
The wall-clock timeout, the output byte ceiling and the rate-limit class are the server's, in the same style as the existing ones.

**The permission bit defaults to nobody.**

`USE_CANVAS` shipping to `@everyone` with no removal path is the cautionary example this repository already has, and it needed three hard ceilings before it could merge.
Running arbitrary code is a larger ask than drawing on a canvas.

## What this settles that 0007 deliberately left open

0007 declined to decide the wire protocol, whether extensions are discovered at startup or registered at runtime, and whether an extension can write messages or only answer with a rendered result.
It said none of that was worth settling until something was being built against it.
Something now is, so:

- **Discovery is at startup, from configuration.** An operator adds the service the way they add a service to their compose file. Runtime registration would let a reachable process announce itself into a deployment, which is the auto-install problem 0007 exists to avoid.
- **The runner answers with a result and cannot write messages.** It gets no capability to post, so the worst a compromised runner produces is a wrong answer in the block that invoked it. Posting is what the in-process modules already do under `message.post`, and that capability is not extended here.
- **The wire is the same additive-only JSON discipline as everything else.** A language the runner does not know is a clean refusal, not a crash, the same way an unrecognised extension-point kind is accepted and ignored.

## Which languages, and why the packs are smaller than they look

The owner's framing was packs: languages that run together get packed into one module for free.
The research found that genuine sharing is rarer than that hopes for, so the rule is worth stating precisely.

There are two real packs and one half-pack:

- **C# and F#** share the .NET WebAssembly runtime, and this is the only case where the second language is close to actually free, because both compilers are themselves managed code rather than native toolchains.
- **C and C++** share one clang frontend, where the second language genuinely is a compiler flag. Both are out of scope here anyway, being compiled.
- **Java, Kotlin and Scala** share bytecode execution, which is free, but each needs its own full native compiler to produce that bytecode, which is not. This is the case that looks like a pack and is not one.

Everything else is a bucket of one, including every interpreted language this record actually covers.
TypeScript is worth naming as a near miss: it rides a JavaScript engine but needs a transpile step, and type stripping is cheap only by discarding the type errors a code runner exists to show you.

So the rule is not "group by shared runtime", because outside .NET there is almost nothing to group.
A language belongs in the runner when a maintained WebAssembly interpreter for it exists and fits the ceilings, and each one is its own artifact.

Lua is the best first language, not Python.
Its interpreter is under a megabyte where Pyodide is seven, so it proves the broker, the protocol and the ceilings at a tenth of the weight.
Python is the one people actually want, and should be second, once the mechanism is known to work.

## What this costs, stated plainly

A self-hoster who wants code execution now runs another container.
That is the cost 0007 chose on purpose, because the alternative is every deployment inheriting the security surface whether they want it or not.

The runner is a real service with a real attack surface, and it is the first thing in this project that exists to run code written by whoever can type in a channel.
It should ship behind an operator's deliberate choice, with the permission bit off, and it should be possible to remove it and have the deployment carry on.

## The ceiling that is not free

A WebAssembly sandbox gives memory limits, filesystem isolation and absent network egress close to free.
It gives nothing at all for wall-clock time: a spinning loop does not self-terminate.
Every system surveyed had to add an external timeout, and slim-m's own module runtime already meters fuel through wasmi for exactly this reason.
The runner needs its own, and it is a build rather than an inherited property.

## Not decided here

Compiled languages, which are declined above rather than solved, and are their own decision if they are ever wanted.

The runner's own internals: whether one process holds every runtime or one per language, how a run is isolated from the next, and what the pool looks like under concurrency.
Riju is the interesting prior art there, since reaching two hundred languages pushed it to one container per language, which is the opposite of packing them together.
None of that changes the boundary this record is about, and it is better settled against a working thing than in advance.
