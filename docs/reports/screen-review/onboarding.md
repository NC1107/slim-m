# Onboarding and server connection

## What this covers

The entry screen ("Where are you joining?") and its two breakpoint brackets, the invite and manual-server dialogs, the sign-in/create-account screen and its nine submit-failure states, the TOFU first-connect and identity-changed screens, the identity chip's three states, and the four notice families (safety, push-disabled, invite-required, the stacked probe notices).
42 screenshots back this report, reviewed independently from three angles: frontend (layout and design-system conformance), UX (copy, hierarchy, dead ends, accessibility), and backend (does the screen's claim match what the server actually does).

## The short version

- The single biggest issue in this area is server error text reaching the screen unedited for any status code the client has no specific handling for, and the codebase already has a helper (`describeApiFailure`) that avoids exactly this and isn't used here - see finding H1.
- The invite dialog has no per-field error targeting, so a field-specific failure (a bad address, an unreachable server) shows nowhere near the field it's about - found independently by frontend and UX.
- ~~Two screenshots (`submit-bad-request-desktop`, `invite-dialog-server-refused-desktop`) show fixture text that doesn't match what the real server actually sends for that scenario, which risks the screenshots being read as documentation of real copy.~~ Fixed 2026-08-10.
- The TOFU fingerprint and identity-changed screens, and the four safety/capability notice screens, are the strongest work in this set: correct security framing, accurate against the server, and no notes beyond one low-severity design-tension observation.
- Sign-in's form fields are raw Material widgets rather than `AppInput`/`AppButton`, a deliberate and documented trade-off rather than an oversight, but still a visible style break next to the dialogs in the same flow.
- No dead ends anywhere in this area: every error and notice offers a way forward, and no state is asserted with colour as the only channel.

## Onboarding screen ("Where are you joining?")

Verdict: clean across every lens.
Three equally-weighted entry cards (invite, manual, official instance), each with an icon, a one-line reason to pick it, and the official address shown up front rather than hidden behind a tap.
No hierarchy asserted between the cards, correctly, since they're three different situations rather than a recommended-vs-alternate choice.
Touch targets are large (full-width cards, ~95px tall at 1x on phone).
Both breakpoint brackets (the stepper's label-collapse at 467/468, the branding rail's move at 899/900) land on the exact pixel the source predicts, with no clipped text or dead space on either side - see Cross-cutting.
Nothing here has any backend surface to check: navigation only, before any request is sent.

One low finding, frontend only:

- `_Entry`'s title `Text` (`onboarding_screen.dart:157-163`) is a bare `TextStyle(...)` rather than `AppText.body.copyWith(...)`, the way every sibling `Text` in the same file is built (`:42-48`, `:165-170`).
  It happens to inherit the right size via `DefaultTextStyle`, so nothing visibly breaks, but it's the one `Text` in this screen not anchored to the `AppText` scale by name.
  Severity: low.
  Fix: `AppText.body.copyWith(color: tokens.textPrimary, fontWeight: AppWeights.semi)`.

## Invite dialog ("Redeem an invite")

Verdict: good `AppInput`/`AppButton`/`AppErrorState` conformance and correct disabled/error states across all 7 captured variants, with two real findings, both about the same underlying gap.

- **No per-field error targeting.**
  Found independently by frontend and UX from two different screenshots of the same root cause: `_InviteDialogState` keeps one `_error` string with no per-field target, unlike `sign_in_screen.dart`'s `_ErrorField` enum, which drives real per-field red borders.
  Frontend, from `invite-dialog-unreachable-desktop.png`: a `TransportException` ("Could not reach that server.") always writes to the shared `AppErrorState` box below the checkbox (`onboarding_screen.dart:243-248`); the Server field above it stays neutral, while `sign_in_screen.dart:285-289` routes the identical failure to a red-bordered field.
  UX, from `invite-dialog-address-error-desktop.png`: the invalid Server field ("not a url") gets no red border and no adjacent error text, the error ("That does not look like a server address.") appears several rows away below the checkbox, and the *Invite code* field is the one wearing the focus ring - so at a glance the wrong field reads as flagged.
  This is invisible by coincidence on the single-field manual-server dialog (see below), but real on this two-field-plus-checkbox dialog.
  Severity: medium.
  Fix: give `_InviteDialogState`/`_ManualServerDialogState` the same `(_ErrorField, String)?` shape `sign_in_screen.dart` already uses.

- ~~**Fixture depicts a response the real endpoint cannot produce** (backend, `invite-dialog-server-refused-desktop.png`).
  The screenshot shows "The server refused that. invites are disabled here", sourced from a synthetic test fixture (`ui_overlay_snapshot_onboarding_test.dart:226`).
  `GET /invites/check/{code}` (`http/invites.rs:214-239`) never consults `join_policy` at all - it only ever returns 200 with `{usable, community}` or a rate-limit/internal error - so there is no server code path that returns a 400 "invites are disabled here" for this route.~~
  Fixed 2026-08-10, the relabel option: the fixture now sends a real 500 with the exact fixed string `ApiError::Internal` always sends ("internal error"), a genuine response this route can produce, rather than an invented 400.
  UX separately flagged the same screenshot's rendering: the second clause is lowercase with no closing period next to a properly-punctuated sibling message, which is the client-side half of finding M4 below - moot now that the fixture text is "internal error", which needs no sentence-case fix.

Everything else checked out clean: the code-unusable message ("That code is not usable. It may have expired or already been used.") matches the server's deliberately uniform `InviteCheck::Unusable` answer exactly (`store/invites.rs:81-86`, `:207-239`) with nothing for the client to leak even if it wanted to; the unreachable, address-error, and scheme-refused copy all read well and match client-only validation with nothing server-specific to check.

## Manual server dialog ("Connect to a Space")

Verdict: clean.
The standing security reminder ("Whoever runs this Space can read the messages sent through it...") shows unconditionally before any error state, which is the right place for it.
Address-error and scheme-refused copy is identical in wording to the invite dialog's and happens to be field-adjacent here - UX notes this is partly luck rather than design, since the single-field layout has nowhere else for the error to land; the same missing per-field targeting (finding above) applies to this dialog's `_ManualServerDialogState`, it's just not visible with only one field.
Backend confirms all three states are pure client-side validation that never reaches the network - nothing to check against the server.

## Sign-in screen ("Welcome back" / "Create an account")

Verdict: functionally correct at every tested width and theme, with real design-system and copy findings.
`Version` fields map 1:1 onto the server's `Version` struct with no probe-result leakage before `/version` answers, the create-account mode carries good continuity (stepper reappears with the invite step marked done, identity chip repeats above the form), and the seven distinguishable submit-error states (`submit-address-error`, `-scheme-refused`, `-rate-limited`, `-server-unavailable`, `-unreachable`, `-username-taken`, `-wrong-credentials`) all name what happened and what to do, each verified to match the exact server condition it claims: rate-limit copy matches the real 6-second token refill, wrong-credentials collapses "no such user" and "wrong password" into one message on one field exactly the way the server's timing-safe uniform 401 is designed to, and username-taken maps precisely to `ApiError::Conflict`.

- **Raw server-message passthrough for unmapped errors.** (High - see H1 in Cross-cutting; also present in the invite dialog via the same code shape.)
  `sign_in_screen.dart:290`'s catch-all - `_ => (_ErrorField.form, 'The server refused that. ${e.message}')` - is reachable for real via `ForbiddenException`, `NotFoundException`, `NotConfiguredException`, or a genuine 500.
  For a mapped exception the message is an intentional, worth-reading string; for the catch-all case it's whatever text was in the response body, never written with a reader in mind.
  The project's own `describeApiFailure` helper (`api_failure.dart`) already solves exactly this for its default case and isn't used by either onboarding screen.
  See Cross-cutting for the full writeup; filed once there rather than twice.

- **Form-level error visually reads as the password field's own error.**
  `_ErrorField.form` failures (rate-limited, unavailable, generic fallback) render as a bare `Text(formError, style: TextStyle(color: tokens.dangerText))` (`sign_in_screen.dart:391-400`) positioned directly under the Password field, with the same alignment and caption-like size a field's own `errorText` would have.
  `submit-rate-limited-desktop.png` sits exactly where a Password-field error would sit, with no spacing, icon, or box telling the two apart; `submit-wrong-credentials-desktop.png` (a genuine password error) is visually identical in every respect.
  Severity: medium.
  Fix: route form-level failures through `AppErrorState` (already used one screen earlier for this) or at minimum add spacing/an icon.

- **The whole form bypasses `AppInput`/`AppButton`.**
  Every field (`sign_in_screen.dart:326-390`) is a raw Material `TextField`, and both primary actions (`:402-425`) are raw `FilledButton`/`TextButton`, while the sibling dialogs one screen earlier use `AppInput`/`AppButton` throughout.
  This is documented rather than silent: `app_theme.dart:38-47`/`:82-99` explicitly theme these Material widgets for "the handful of call sites that never reached for `AppButton`/`AppIconButton`", and colours are applied consistently.
  What the Material theme doesn't replicate is `AppInput`'s specific chrome - the dual focus ring versus Material's single 2px `focusedBorder` (`input.dart:190-202` vs `app_theme.dart:203-206`) - and the floating label affordance `AppInput` has no equivalent for.
  Side by side (`sign-in-desktop-light.png` against `invite-dialog-empty-desktop.png`), the two field styles are visibly different treatments of the same concept seconds apart in the same flow.
  Severity: medium (visual inconsistency, not a functional bug, and a reviewed trade-off rather than an unnoticed regression).
  Fix, if ever revisited: extend `AppInput` with `labelText`/`helperText`/`autofillHints` (`design_system/lib/src/components/forms/input.dart:23-79` has none of these today) so this screen can adopt it without losing autofill.

- ~~**`submit-bad-request-desktop.png`'s fixture text doesn't match the real server message.**
  The screenshot shows "password must be at least 8 characters" (lowercase, no period), sourced from a test fixture (`ui_overlay_snapshot_signin_test.dart:340`).
  The real server message for this exact validation failure is "password must be 8 to 1024 characters" (`http/auth.rs:276-284`, `validate_password`) - close enough to look authoritative but not what a real client would receive.~~
  Fixed 2026-08-10: the fixture now sends the real string verbatim.
  This also happens to be the clearest instance of the sentence-case defect (finding M4 in Cross-cutting): "password must be..." breaks from every other message on this screen, all of which are hand-written and sentence-cased - that half is **still open**, since it's a property of the real server string the fixture now correctly reproduces, not of the fixture itself.
  Severity: medium (fixture/documentation accuracy on top of the client-side capitalization bug).
  Fix: change the fixture to the real server string, and apply the sentence-case fix from M4.

- **Identity status glyph carries no visible text for a sighted user.** Frontend and UX disagree on how much this matters, and both readings are kept.
  The three identity states (`identity-chip-unknown/-confirmed/-mismatch-desktop.png`) are distinguished only by a 16px glyph at the edge of the chip row (nothing for unknown, a blue check for confirmed, a red-outlined exclamation for mismatch), with no visible label or tooltip - `_IdentityStatusGlyph` (`onboarding_shell.dart:389-423`) wraps the icon in a `Semantics` label only, so a sighted, non-screen-reader user has no on-screen words for what changed until they press Submit.
  Frontend calls this medium: this is the passive warning for a possible impersonation attempt, and relying on an unlabelled icon is a legibility gap for a security-relevant signal.
  UX calls it low: it's a sighted-user-only gap (screen readers are fully covered), and it isn't a security hole, since submitting still routes through the full-screen TOFU `ServerIdentityChangedStep` (`sign_in_screen.dart:222`) regardless of whether anyone noticed the chip - a discoverability nicety, not a gate.
  Fix either way: wrap `_IdentityStatusGlyph` in a `Tooltip` using the `_labels` map it already has for `Semantics`, so hovering or long-pressing surfaces the same sentence a screen reader gets.

## TOFU fingerprint / identity-changed screens

Verdict: excellent, and unanimous across all three lenses. No findings.

`ServerFingerprintStep` and `ServerIdentityChangedStep` use `AppButton`/`AppCallout` correctly, the danger-variant "Trust the new identity" button's disabled-vs-enabled states are visually distinguishable, and nothing overflows at the 420px content width.
The security framing is correct and doesn't overclaim: amber (not red) tone for a routine first connection, the caveat that TOFU "only protects connections after this one" is stated rather than implied, and the fingerprint renders two ways at once (word-list and four coloured dots) so confirmation doesn't rest on colour or hex alone.
The changed-identity screen is the standout: heading shifts to danger red, the explanation covers honest and dishonest causes in plain language, the destructive action is gated behind an explicit checkbox with the button itself dimmed until it's ticked, and even once enabled the button is outlined red rather than filled, matching the project's own rule that danger is never a filled button.
Cancel carries equal visual weight, so it isn't a dead end.
Backend confirms the fingerprint and colour strip come straight from `ServerIdentityDto` (`http.rs:218-234`, Ed25519-derived, never from TLS) and that the changed-identity flow requires its own explicit acknowledgement distinct from - and harder to tap through than - the routine first-connect step, matching the module's own stated intent.

## Notices (safety, push-disabled, invite-required, the stacked probe)

Verdict: strong across all three lenses, with one low design-tension note.

All four safety-notice variants (missing both, missing block, missing report, unknown/too-old-to-say) render distinct copy and icons, and the copy is a genuinely good piece of writing: each state names the actual consequence before the reassurance ("If someone here harasses you, the app has nothing to do about it. You can still join.") rather than a templated list.
Backend confirms this is the exact distinction it needs to be: `SafetyTools.unknown` (server sent no `capabilities` key) and `SafetyTools.missing` (key present but incomplete) are structurally different server answers, verified never to be conflated, and the capability list itself is derived by probing the live router (`http/capability.rs:62-88`) rather than kept by hand, so `capabilities` on `/version` genuinely reflects what the binary serves.
Push-disabled and invite-required notices both name the real limitation and, for invite-required, the remedy and who can act on it - backend confirms `Version.pushEnabled`/`inviteRequired` map directly to the server's own state with no cross-wiring, and that "an admin can open joining to anyone in Settings, under Space" is accurate.
The three-notice stack orders and spaces with no overlap.

- **`probe-notices-stacked-desktop.png`: the safety-tools warning carries the same visual weight as the purely informational notices.** (UX only.)
  All three stacked notices render in identical neutral grey with identical icon weight via the same `ServerNotice` component - a documented, deliberate choice per that widget's own doc comment ("Never a blocker... the job is to inform the person joining, not to decide for them"), so this isn't a bug.
  But "this server cannot tell you who's harassing you" reads with the same weight as "this server can't push to your phone," and in a stack of three the safety-tools warning is easy to skim past as one more informational line rather than the one substantively different in kind.
  Severity: low (design tension, not a defect).
  Fix: consider giving the safety-tools notice alone a warmer amber treatment, consistent with how the TOFU first-connect screen already uses amber for "worth pausing on but not alarming," while leaving the other two notices as they are.

## Cross-cutting

- **H1. Raw server-supplied error text reaches the screen unedited for any status code the client has no specific handling for, and this is the single biggest issue in the set.**
  All three lenses converge on this from different angles, with UX rating it highest.
  Two call sites share the identical shape: `sign_in_screen.dart:290`, `_ => (_ErrorField.form, 'The server refused that. ${e.message}')`, and `onboarding_screen.dart:247`'s matching invite-dialog case.
  `submit-generic-refusal-desktop.png` shows "The server refused that. teapot" - the 418 stimulus is a test fixture, but the branch itself is reachable for real via `ForbiddenException`, `NotFoundException`, `NotConfiguredException`, or a genuine 500, none of which are written with a reader in mind for their raw text.
  Backend confirms the floor isn't as bad as it could be - `ApiError::Internal` is always the fixed string "internal error" (`http/error.rs:80`), never a stack trace or type path - but nothing stops a future unmapped `ApiError` variant, or a proxy/gateway error the client's `switch` doesn't branch on, from putting arbitrary text in front of a user, styled as authoritative product copy.
  The project's own `describeApiFailure` helper (`api_failure.dart`) already gets this right for its default case (`api.ApiException() => 'Could not $whatFailed.'`, deliberately omitting `e.message`, with a doc comment stating `TransportException.message` "is a log line, not copy"), and neither onboarding screen uses it - each has its own `switch` that reintroduces the exact leak the helper exists to prevent.
  Severity: high.
  Fix: route both catch-alls through `describeApiFailure` (or the same never-show-raw-message-for-an-unmapped-exception rule).

- **M4. Raw server message text breaks sentence case where it does reach the screen.**
  Frontend and UX both flag this, from `submit-bad-request-desktop.png` ("password must be at least 8 characters", lowercase, no period) and `invite-dialog-server-refused-desktop.png` ("...refused that. invites are disabled here", lowercase second clause, no period) - both interpolate `ApiException.message` directly with no normalization, next to hand-written, sentence-cased, punctuated strings everywhere else on the same screens.
  This is reproducible any time a mapped exception's server-authored message happens to be lowercase, independent of finding H1 above.
  Severity: medium.
  Fix: a small `_sentenceCase(String)` helper (capitalize first letter, ensure a trailing period) applied wherever a raw `e.message` is interpolated into either screen's error copy.

- **No design-system checkbox exists.**
  `CheckboxListTile` (raw Material) is used identically in the invite dialog's terms-acceptance row (`onboarding_screen.dart:292-301`) and the identity-changed acknowledgement row (`server_identity_changed_step.dart:84-94`).
  There is no `checkboxTheme` in `app_theme.dart`, so both render with Material 3's default shape/sizing; the checked-state fill happens to land on-brand only because `ColorScheme.primary` is pinned to `tokens.accentFill` (`app_theme.dart:107`).
  Consistent with itself across both uses, so not a drift bug, but a real gap in the component library relative to `AppInput`/`AppButton`'s coverage.
  Severity: low.
  Fix: an `AppCheckbox` component, or at minimum a `checkboxTheme` entry in `buildTheme`.

- ~~**Two fixture strings don't match what the real server sends, and nothing guards them against drift.**~~
  Fixed 2026-08-10, both (see each finding above for what changed). Not closed at the mechanism the finding's own doc comment names, though: nothing yet guards either string against drifting away from the server again the way `mention_charset_cases.json` guards the mention regex - that would need a new shared fixture, which is a larger change than a two-string fix and was not attempted here.
  Backend-only, spanning `submit-bad-request-desktop.png` and `invite-dialog-server-refused-desktop.png` (both detailed under their screens above).

- **Every breakpoint the capture set deliberately brackets lands on the exact pixel the source predicts.**
  The stepper's label-collapse (467 vs 468) and the branding rail's move into a persistent left column (899 vs 900) both flip exactly where `onboarding_shell.dart:22` and `:195` say they should, with no clipped text, overlap, or dead space on either side.
  Not a coincidence: both thresholds were clearly built and tested against exactly these boundaries.
  No fix needed; recorded as a positive.

- **Colour is never the only channel anywhere in this area.**
  Every status-bearing element (TOFU amber vs. red, the identity-chip glyphs, danger buttons) also carries a shape, icon, or text difference.
  The one place a sighted user gets less than a screen-reader user is the identity chip's glyph (see the Sign-in screen finding above), which is a discoverability gap, not a colour-alone violation.

- **No dead ends found anywhere in this area.**
  Every error and notice screen offers a way forward: retry, cancel, "Join a different Space," or (for identity-changed) an explicit, gated override.
  The one near-miss - `invite-required-notice-desktop.png`, a manually-typed address that turns out to require an invite - still leaves "Join a different Space" live.

- **No instance found of a raw exception, Rust type path, stack trace, or request body leaking into rendered text.**
  Confirmed by reading `http/error.rs`'s full `IntoResponse` impl rather than just the happy-path handlers: `ApiError::Internal` is always the fixed string "internal error", and every other variant carries only a deliberately-authored static string.
  This bounds how bad finding H1 above can get in practice today, even though the client-side gap that would let a future unmapped message through unedited is still real.

- **Touch targets are comfortable throughout** the phone-width screens reviewed (onboarding cards, sign-in fields and buttons, the revoke-invite bottom sheet) - nothing measured near the 44px floor.
