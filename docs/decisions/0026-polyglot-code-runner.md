<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# 0026 - One runner service for the common languages, modules for the odd ones

Status: proposed, 2026-09-16.
Amended the same day.
The runner is not ours to build and it is not WebAssembly; see "What changed, and why" at the end.
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

**That service is Piston, and we do not build it.**

The owner's instruction, after reading how Piston works: stop treating this as exotic, and put the trust decision in the operator's hands rather than in a sandbox we design.

[Piston](https://github.com/engineer-man/piston) is the code sandbox most chat bots already use, self-hosted in docker, and on 2026-09-16 its public instance advertised **87 runtimes including python 3.10**.
So slim-m speaks Piston's protocol and an operator runs Piston.
There is no runner service in this project, now or later.

That is a smaller decision than the one this record originally made, and a better one on every axis that matters here.
Every language arrives at once rather than one per release, so the bucketing question this record was built around stops mattering: Piston already did that work, for eighty-seven runtimes.
Its `GET /api/v2/runtimes` says what a given instance actually has, so the deployment asks rather than carrying a hardcoded list, and a language the operator's instance lacks simply gets no Run button.

**The isolation is Piston's, and we do not reimplement it.**

It runs each submission as a different unprivileged user in its own linux namespaces, with outgoing network off by default, processes capped at 256, files capped at 2048, cpu and wall time capped at three seconds, a peak memory cap, stdout truncated at 1024 characters, temp space cleaned after every run, and SIGKILL for anything that misbehaves.

Claiming to add to that would be pretending.
What this project owes an operator instead is a plain warning at the point they enable it: do not turn this on if you do not trust the people in your space.

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
- **The wire is Piston's `POST /api/v2/execute`, not ours.** This was written as an open question and answered by not inventing one: a contract we design is a contract we maintain, and matching Piston's means an operator points slim-m at a stock instance with nothing in between.

## Which languages

Whatever the operator's Piston instance has installed, asked at runtime rather than decided here.

The research in [docs/research/code-runner-languages.md](../research/code-runner-languages.md) spent its length working out which languages could share an artifact, and the answer was two real packs and a long tail of singletons.
That analysis is now moot for this decision and is kept because it is still the honest record of why the WebAssembly route was abandoned: no compiled language has a WebAssembly-hosted compiler in production anywhere, which is exactly why every existing system, Piston included, uses native toolchains in a container.

Python is the language the owner asked for and the one to verify against first.

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

## What changed, and why

This record was written and amended on the same day, and the amendment reversed its central mechanism, so the reasoning is kept rather than tidied away.

As first written it proposed a runner service **we** would build, with **WebAssembly** interpreters inside it, one language at a time, starting with Lua because its interpreter is small.
Two things killed that.

The research found that no compiled language has a WebAssembly-hosted compiler in production anywhere, which already narrowed the record to interpreted languages only.
Then the owner pointed at Piston and asked why we were designing a sandbox at all.
The honest answer was that we should not be: Piston is the thing every comparable product already uses, it carries eighty-seven runtimes, and its isolation rules are more thorough than what this project would have written for itself.

The WebAssembly route was not wrong so much as **it was solving a problem that a maintained service had already solved**, and it would have arrived one language at a time over months.
Lua as a first language existed only because a WebAssembly interpreter is small, which stopped being a consideration the moment we stopped shipping interpreters.

What survives unchanged from the original is everything about the boundary, because that half was never about the backend: the server brokers and never executes, an invocation carries the block and nothing else, absent configuration is a normal state, the permission bit defaults to nobody, and the ceilings are the server's own.
