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

**Inside that service, each language is a WebAssembly runtime, not a native one.**

This is the part 0007 could not have written in August, because it predates the module runtime existing.
It matters because it gives two independent boundaries rather than one.
The service boundary bounds what a compromised runner can reach, which is nothing of ours.
The WebAssembly boundary bounds what one run can do to the runner, so a person who hangs a Python interpreter does not take out somebody else's Ruby.

Precompiled runtimes for this exist and are maintained: `componentize-py` and `RustPython` both had commits this month.
The older VMware collection has not moved since 2024 and should be treated as a reference rather than a dependency.

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

## Which languages

Deliberately not settled here beyond the rule.

A language belongs in the runner when a precompiled WebAssembly runtime for it is maintained and fits the ceilings.
A language belongs in its own module when it does not, or when it needs something the shared contract cannot give it.
Python is the obvious first, because it is what prompted this.

The point of the split is that adding the second language should not be an architectural event.

## What this costs, stated plainly

A self-hoster who wants code execution now runs another container.
That is the cost 0007 chose on purpose, because the alternative is every deployment inheriting the security surface whether they want it or not.

The runner is a real service with a real attack surface, and it is the first thing in this project that exists to run code written by whoever can type in a channel.
It should ship behind an operator's deliberate choice, with the permission bit off, and it should be possible to remove it and have the deployment carry on.

## Not decided here

The runner's own internals: whether one process holds every runtime or one per language, how a run is isolated from the next, and what the pool looks like under concurrency.
None of that changes the boundary this record is about, and it is better settled against a working thing than in advance.
