# 0024 - Silent sign-outs are diagnosed before they are fixed

Date: 2026-09-13
Status: accepted (diagnosis); the remedy is deliberately deferred

## Context

The owner reported "I also keep getting logged out of the app."

There is exactly one involuntary sign-out path in the client.
`client_auth.dart::_refreshOnce` clears the session when a refresh comes back 401, and nothing else ends a session without the user asking.
So every instance of this report is a refresh that was rejected.

A refresh is rejected for four reasons, and `http/auth.rs` deliberately collapses all of them into one bare 401: "a benign miss and a detected replay look identical to the client".
That is right for an unauthenticated caller and it is why nobody, including the person it happens to, can say which one occurred.

## The window that makes this possible at all

Access tokens live 15 minutes and refresh tokens are single-use, so every client rotates roughly four times an hour, forever.
A rotation commits server-side before its response reaches the client, and the old token is spent at that moment.

`SessionStore.settled`'s own doc already names the consequence: "a process death between that response and the new token reaching disk replays the old, now-spent one on the next launch and gets read as reuse".
`_refreshOnce` awaits that write to narrow the window, but the wait is bounded at five seconds and then proceeds regardless, and no wait can cover a process that dies mid-write.

The server's 10-second reuse grace (`DEFAULT_REUSE_GRACE_MS`) does not rescue this.
Within the grace a replay is not treated as a leak, which protects the *family* - but the response is still a 401, and the client clears the session on any 401, so the user is signed out anyway.
The grace window buys the deployment something and buys the person nothing.

## What was ruled out

- **Deploys losing in-flight responses.** Plausible on a continuously-deployed main, but `lib.rs` already serves `.with_graceful_shutdown(shutdown_signal())` on SIGTERM, so requests drain.
- **A 401-retry loop double-spending the token.** `client_transport.dart` guards its retry with `authenticated && !isRetry`, and the refresh call itself is unauthenticated, so it cannot recurse.
- **The FCM background isolate refreshing behind the app's back.** It makes no API calls; `firebaseMessagingBackgroundHandler` only renders a local notification from a content-free envelope.
- **Concurrent rotations inside one app.** `refresh()` shares one in-flight rotation, because the refresh token is single-use.

What remains: a new pair that never reached storage, or a second process that spent it.
Both look identical from the sign-in screen, which is why this record ships an instrument rather than a fix.

## Decision: measure first

The client now records *why* it signed you out, in terms that separate the survivors rather than the terms the server used.
`SessionStore.describeRejection` distinguishes:

- a rejection on a pair this process never rotated -> what was stored was already dead
- a rejection N seconds after a rotation, and whether that rotation reached storage -> this process raced itself or lost the response

That reaches the in-app debug log through `installDiagnostics`, so the next occurrence is a line the owner can read and quote.
The server now logs a reason on every rejected refresh too; only the reuse case was logged before, so three of the four causes were invisible on both sides at once.

## The remedies, and why none of them is taken yet

Each of these trades something real, and the choice belongs to the owner once there is evidence of which cause is actually biting.

**1. Leeway: serve a replay inside the grace window instead of denying it.**
Cannot return the *same* pair - refresh tokens are stored hashed, so the server cannot reproduce the plaintext it issued - so it would mint a fresh one.
Fixes lost responses and lost writes alike.
Costs: an attacker replaying inside the window gets a working session, where today they get nothing.
It also cannot be conditioned on "the successor is still unused" to narrow that, because the honest self-race and the lost response are identical under that test, and re-issuing during a genuine self-race would strand the pair the client is holding.

**2. Delayed invalidation: keep the old token usable until its successor is first used.**
Fixes the same cases and is a clean rule.
Costs detection: the leak signature becomes "old used after new used", so an attacker who gets in first hijacks the session rather than tripping a revocation that logs everyone out.

**3. Lengthen the access-token TTL.**
Fewer rotations is proportionally fewer chances to lose one; changes no security property except the window a stolen access token is useful for.
Does not fix anything, only reduces frequency.

This is a self-hosted deployment for one small community, and the threat being optimised for - an attacker holding a stolen refresh token - is considerably less likely than the cost being paid, which is the owner being signed out repeatedly.
That argues for (1) or (3).
It is still not a change to make on a hunch about which cause is firing, which is what the instrument above is for.

## Consequences

- A silent sign-out becomes a line in the debug log naming its likely cause.
- The wire is unchanged: the 401 stays indistinguishable, so nothing here tells an attacker anything.
- The remedy is a follow-up, gated on one real observation rather than on this reasoning.
