# 0052 - /version says whether the deployment is claimed

Status: accepted, 2026-10-01.

## The report

A brand new deployment opened on "Welcome back" sign-in.
The client could not tell an unclaimed deployment from a claimed one, because `invite_required` reads true before anyone has registered.

## What changed

`GET /version` carries `claimed: bool`, true once the first account has registered (`Store::is_bootstrapped`).
It is additive and absent on older servers, which a client reads as unknown and treats like claimed.

## Why it is safe on an unauthenticated route

`/version` is unauthenticated and rate limited, and already reveals deployment configuration only.
Whether a deployment has an owner is already observable by calling `POST /auth/register`: an unclaimed one accepts a first account with no invite, a claimed one refuses without a code.
The field exposes that same fact without the side effect of claiming it, so it adds nothing an attacker could not learn, and one indexed lookup is the whole cost.

## The client landing

Unclaimed (`claimed == false`): the first-run flow opens on create-account with owner-claim wording ("the first account becomes the administrator").
Claimed or absent: it opens on sign-in, as before.
A person who has chosen a mode by hand is never switched under them.
