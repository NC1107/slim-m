# Notification Audio System

Scope: the seven-sound notification family (direct message, mention, group message, call ring, member join, member leave, error), the Python synthesis pipeline that produces them, loudness normalization, and per-OS playback integration.
This system touches only client assets and client-side playback code.
It has zero runtime footprint on the self-hosted server, worth stating up front since the brief's audio section sits next to server-focused requirements and could be misread as adding a server dependency.

## Synthesis pipeline: Python as a build-time tool, never a runtime dependency

Decision: numpy generates each waveform as pure deterministic additive synthesis, no noise components, no random seeds to manage, and `pyloudnorm` (an ITU-R BS.1770 implementation) normalizes loudness in the same script before the file is written.
Each sound gets its own `generate_<name>.py` under `assets/audio/notifications/`, committed next to the WAV file it produces, plus one `generate_all.py` that regenerates the full set.
A CI job reruns the generators and diffs the output against the committed WAVs, failing the build on any mismatch.
This is what actually enforces the brief's "generator scripts committed alongside their waveforms" requirement, rather than leaving it as a documentation convention nobody checks.
Rejected: a DAW-authored or sample-based sound set, not reproducible from source and impossible to regenerate deterministically when a parameter changes.
Rejected: shipping numpy or pyloudnorm as an app or server dependency, violating the lightweight-server principle for what is entirely a one-time asset build step.
Risk: numpy version drift changing floating-point output between contributor machines, mitigated by pinning exact versions in a `requirements.txt` used only by the CI regeneration check.

## One shared sonic language, seven distinguishable members

Decision: every sound uses the same synthesis voice, a soft bell-like additive tone built from a fundamental plus two slightly inharmonic partials (ratios near 1x, 2.4x, 3.8x, evoking a marimba or chime rather than a pure sine beep), with a fast 10 to 15ms attack and an exponential decay, no sustain phase.
Sounds are told apart by pitch contour, note count, and duration, not by switching timbre, the same discipline that makes GNOME's and macOS's system sounds feel like one family instead of seven unrelated beeps.
Direct message: a single rising two-note interval (major third), about 250ms, mid register around 520 to 660Hz.
Mention: the same rising shape extended to three notes, slightly brighter and 100ms longer, so it reads as one step more urgent than a plain DM without changing character.
Group message: a single short note, lower amplitude and the shortest duration in the set (under 150ms), deliberately the least attention-grabbing sound since it is the one most likely to fire often.
Member join and member leave: a mirrored pair, join rises two notes, leave plays the identical two notes in reverse, so learning one teaches the other.
Call ring: the only looping sound, a slow two-note pattern with real silence between repeats (roughly 1s on, 2s off) rather than a continuous tone, capped at a 30-second auto-stop to bound worst-case exposure.
Error: a soft descending minor second, timbrally duller than the rest (partials rolled off harder), reading as negative in valence without becoming an alarm.
Rejected: a distinct synthesis method per sound for more variety, which would break the family cohesion that lets users learn the set quickly.
Risk: a two-note vocabulary runs out of room as more event types are added, mitigated by reserving the three-note and mirrored-pair patterns already used by mention and join/leave as the escalation path.

## Psychoacoustic guidelines

Fundamentals stay in the 400 to 1200Hz band, low enough to avoid the thin, piercing quality of very high tones on small speakers, high enough to stay clear of the muddy low end phone and laptop speakers reproduce poorly.
Nothing has content below 150Hz, which only adds rumble or distortion on hardware that cannot render it.
A gentle low-pass above 8kHz removes synthesis artifacts that add harshness without adding perceptible information.
Every sound starts at a true zero-crossing with no leading silence, so playback feels instant rather than laggy, and ends with a 5 to 10ms fade to avoid a truncation click.
Everything is mono: notification sounds do not benefit from stereo width, mono avoids phase issues when an OS notification pipeline downmixes anyway, and it keeps files small enough that compression is not worth the added format complexity (each file lands under 50KB uncompressed, the full set under 350KB).

## Loudness normalization and LUFS targets

Integrated LUFS is unreliable below roughly 3 seconds because BS.1770 gating needs 400ms blocks to stabilize, so one-shot sounds and the loop use different measurements.
One-shot sounds (direct message, mention, group message, member join, member leave, error): normalized to -18 LUFS momentary maximum, true peak ceiling -3 dBTP.
The call ring loop, long enough for integrated measurement to be meaningful: -23 LUFS integrated (standard EBU R128), same -3 dBTP true peak ceiling.
Both targets are applied inside the generator scripts via `pyloudnorm`, so every commit produces consistently measured output, with no runtime DSP or gain stage needed at playback time.
On "normalized across operating systems": read literally, this could mean forcing identical absolute output level regardless of the user's OS volume setting, which would be a bug, since OS notification volume is a user-facing control the app has no business overriding.
The achievable version of that goal is consistent relative loudness within the seven-sound family, fully within the app's control, while absolute loudness at the ear correctly stays subject to the user's own volume and mixer settings.
I recommend STRATEGY.md adopt this narrower reading explicitly so it is not later treated as a bug that the app "isn't as loud on Linux as on iOS" when the user's own mixer explains the difference.

## Per-OS playback integration

Foreground playback uses one Flutter audio plugin across all three platforms so there is a single code path to maintain, not three.
iOS: the in-app player uses the `.ambient` `AVAudioSession` category so notification sounds respect the physical silent switch, matching how well-behaved apps like Slack behave rather than overriding a user's explicit mute.
Background push notification sound is a separate integration entirely: APNs requires a file bundled in the app, linear PCM or IMA4 inside a `.caf`, `.aiff`, or `.wav` container, 30 seconds or under, referenced by filename in the payload.
A missing or misnamed file fails silently, iOS falls back to the default tri-tone with no error surfaced, so a CI check verifies every sound referenced in code exists in the built iOS bundle.
CallKit's incoming-call ringtone is a third, fully separate path, its own bundled file under the same 30-second limit, worth naming since it is easy to assume the regular notification pipeline covers it and it does not.
Android: background sound plays through a Notification Channel, and a channel's sound locks in permanently at creation, an app update cannot change it for existing installs.
Channel IDs must be versioned from day one (`channel_message_v1`) so a future sound change means creating `channel_message_v2`, not discovering the old sound is stuck forever.
Linux: the relay only targets mobile devices per the brief's own networking design, so Linux has no background wake case at all, every Linux notification sound is foreground and app-owned, played directly through PipeWire rather than relying on `notify-send` or desktop sound themes, whose default-sound behavior varies across GNOME, KDE, and other environments.

## A concern worth flagging

Member join and leave sounds are structurally at odds with the "quiet, pleasant" goal in any group above a handful of members, no mix design fixes a sound that fires fifty times a minute in a busy server.
This is a scope and defaults problem, not an audio problem: join and leave sounds should default off above a small member-count threshold and stay on only for DMs and small groups, with a per-channel mute always available.
I recommend STRATEGY.md capture this as a notification-settings requirement now, rather than letting it surface later as a spam complaint that looks like an audio design failure but is actually a missing default.

## Open questions

- The exact member-count threshold at which join and leave sounds default to off, likely a product decision rather than an audio one.
- Whether call ring should get a second, louder variant for the CallKit-integrated incoming-call case specifically, since it competes with the OS's own ringtone volume path rather than the app's in-process player.
- Whether future non-notification UI sounds (send confirmation, canvas actions) should reuse this same synthesis voice and pipeline, likely yes, but out of scope for this report.
