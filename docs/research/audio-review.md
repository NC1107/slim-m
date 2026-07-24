# Notification Audio System: Adversarial Review

Status: pre-implementation critique of `docs/research/audio.md`.
Scope: the same axes the report itself covers, plus consistency against `docs/BRIEF.md` and the sibling research reports it should have been reconciled with, specifically `networking-relay.md`, `security.md`, `flutter-client.md`, `media.md`, and `appstore.md`.
Severity is reserved for "critical" only where the finding would force a redesign before implementation starts.

## Summary

The synthesis pipeline, sound-family discipline, and psychoacoustic guidelines are well argued and internally consistent on their own terms.
The report's weakest point is exactly where it touches subsystems it does not cite: the background push-notification sound design assumes a plaintext payload the project's own committed push architecture does not provide, because the relay and the home server already agreed, in `networking-relay.md` and `security.md`, to send only ciphertext and a coarse four-value event kind.
That single unreconciled assumption is a critical finding, since it invalidates the report's entire "referenced by filename in the payload" claim for background sound selection.
Beyond that, the report understates the implementation cost of its own loudness targets, leaves the most complex sound in the set (the call ring) unscoped against CallKit's ownership of the real incoming-call UX on the brief's top-priority platform, and never mentions a shared code path across the seven generator scripts despite the project's stated code-quality principles.

## Critical findings

### 1. Background sound selection assumes a plaintext payload that the committed push architecture does not provide

Target: "Per-OS playback integration" in audio.md, specifically "APNs requires a file bundled in the app... referenced by filename in the payload," and the parallel Android claim that "background sound plays through a Notification Channel."

Weakness: `networking-relay.md` and `security.md` both already committed to an end-to-end encrypted push design.
`/v1/send` carries `{token, platform, kind, ciphertext, collapseId, priority}`, where `kind` is only `message`, `mention`, `call`, or `wake`, and `ciphertext` is opaque to the relay.
On iOS the relay sends a `mutable-content: 1` push with a static fallback alert and the ciphertext in a custom data key.
A Notification Service Extension decrypts on-device and replaces the fallback text, exactly the pattern security.md describes for Signal and WhatsApp.
The home server never puts a plaintext sound filename into the payload the relay forwards, because the relay only ever sees ciphertext plus one of four coarse kinds, not one of the seven sound categories audio.md designed.
Audio.md's iOS section was written as if the payload were a plain APNs JSON dictionary the home server controls directly, with no acknowledgment that sound selection would have to happen inside the Notification Service Extension after on-device decryption, and no design for how the extension picks among the seven bundled files from a decrypted event that is not even guaranteed to distinguish a direct message from a group message, since both collapse into the same `message` kind at the relay layer.
Android has the same gap in a different shape: the FCM message is data-only with no `notification` block, so the app's own code decides which channel to post to only after it has decrypted the payload client-side, which the report never states either.

Failure mode: implemented as written, every backgrounded push plays whatever sound the static fallback or the default channel resolves to, not the sound the seven-member family was designed to distinguish, because the plaintext event type needed to pick a sound never reaches the OS notification layer without extra work the report does not scope.
At best this means direct messages and group messages sound identical in the background, since the relay-visible `kind` cannot tell them apart.
At worst a missing or mismatched sound reference silently falls back to Apple's default tri-tone, the exact failure mode audio.md itself warns about for a "missing or misnamed file," except here it is not a filename typo but a structural mismatch between a four-value kind vocabulary and a seven-sound design.

Resolution: redesign the background-sound section against the actual push architecture.
The Notification Service Extension must select the sound after decryption, which means the decrypted plaintext payload needs to carry enough information to choose among the bundled files, and the extension needs to call `UNMutableNotificationContent.sound` explicitly rather than relying on a payload-level filename reference.
Scope which of the seven sounds even need a background path at all: join, leave, and error have no corresponding relay `kind` and by this project's own push design can only ever fire while the client is foreground and connected, so they need no APNs or channel treatment.

## Major findings

### 2. "Momentary maximum" LUFS is not what pyloudnorm's public API measures, and is undefined for the shortest sound in the set

Target: "Loudness normalization and LUFS targets," the -18 LUFS momentary maximum target for one-shot sounds, "applied inside the generator scripts via `pyloudnorm`."

Weakness: pyloudnorm's public interface implements ITU-R BS.1770 gated loudness measurement, exposed as `Meter.integrated_loudness()`, the same algorithm EBU R128 calls integrated loudness.
It does not expose a momentary (400ms sliding window, updated every 100ms, take the running maximum) measurement as a public method.
Getting a true momentary-maximum figure requires hand-rolling a sliding K-weighted RMS calculation on top of pyloudnorm's internal filter classes, real engineering work the report's phrasing "applied... via pyloudnorm" presents as a drop-in call.
The problem compounds for the shortest sound in the set: the group message sound is specified as "under 150ms" duration, shorter than the 400ms window a momentary measurement requires, so "momentary maximum" is not just harder to implement than stated, it is mathematically undefined for that specific sound.

Failure mode: whoever writes `generate_group_message.py` discovers there is no pyloudnorm call that does what the spec asks, and has to choose an undocumented fallback, such as treating the whole clip as one block and taking its K-weighted RMS, a different measurement than the "momentary maximum" the spec names, silently diverging from the stated target with no test catching the drift.

Resolution: define the actual measurement method explicitly for sub-400ms clips, most likely whole-clip K-weighted RMS as a documented substitute for true momentary loudness, and state in the report that this requires custom code on top of pyloudnorm's filters, not a call to `integrated_loudness()`.

### 3. The CI regenerate-and-diff check is exposed to cross-architecture floating-point drift that version pinning does not fix

Target: "A CI job reruns the generators and diffs the output against the committed WAVs, failing the build on any mismatch," and the stated mitigation, "pinning exact versions... used only by the CI regeneration check."

Weakness: numpy's floating-point summation order and the specific SIMD code path it takes can differ between CPU architectures, for example an Apple Silicon (arm64) contributor machine versus an x86_64 GitHub Actions runner, even when both install the identical pinned numpy version.
Pinning the version controls one axis of drift, the one the report names, but not the architecture axis, which the report does not mention at all.

Failure mode: a contributor generates and commits a WAV locally on arm64, it matches their local regeneration bit-for-bit, and CI on an x86_64 runner produces a different byte sequence for the same script and the same pinned numpy version, failing the build on a PR that never touched the audio pipeline.
This either blocks unrelated PRs or trains the team to treat the reproducibility gate as unreliable and start ignoring its failures, defeating the entire point of the check.

Resolution: pin the CI runner architecture explicitly to match whatever architecture produced the committed reference WAVs, or better, generate and commit the WAVs only from CI itself rather than from contributor machines, so there is exactly one architecture in the reproducibility loop.

### 4. The call ring sound's real applicability on iOS, the brief's top-priority platform, is unscoped

Target: "Call ring: the only looping sound... roughly 1s on, 2s off... capped at a 30-second auto-stop," read together with the report's own admission that "CallKit's incoming-call ringtone is a third, fully separate path."

Weakness: `media.md` and `appstore.md` both already commit to CallKit as the mandatory, App-Store-compliant path for the incoming-call experience on iOS, driven by a PushKit VoIP push, reporting to CallKit synchronously on every delivery.
When CallKit is in play, iOS shows its own native call screen and plays CallKit's own bundled ringtone file, not the app's in-process `AVAudioPlayer`.
That means the elaborate 1s-on/2s-off, -23 LUFS looped design audio.md specifies as "call ring" is, on iOS, only ever heard in a narrower context than the name suggests, most plausibly an outgoing ringback tone while the caller waits, not the incoming ring a callee hears, since the incoming ring on iOS is CallKit's bundled file, a separate asset the report itself flags but never designs.
The report's own second open question, "whether call ring should get a second, louder variant for the CallKit-integrated incoming-call case," shows the specialist noticed the seam without resolving which platform and which call direction the primary "call ring" sound actually serves.

Failure mode: the team designs, generates, loudness-normalizes, and tests a sound built for a use case (incoming ring, foreground, in-process playback) that iOS structurally routes around via CallKit, discovering only in QA on the brief's primary testing platform that the sound they polished is not the one users hear when a call comes in.

Resolution: scope "call ring" explicitly by platform and call direction: what plays as an outgoing ringback on all three platforms, what plays as the Android/Linux in-app incoming ring, and what ships as the separate CallKit-bundled incoming-ring asset on iOS, before generating any of them.

### 5. Seven generator scripts with no shared synthesis module invite exactly the code duplication the brief's code-quality section warns against

Target: "Each sound gets its own `generate_<name>.py`... plus one `generate_all.py` that regenerates the full set."

Weakness: the report describes seven independent scripts sharing one synthesis voice (the inharmonic 1x/2.4x/3.8x partial ratios), one envelope discipline (10-15ms attack, exponential decay, 5-10ms fade), and one set of psychoacoustic constraints (150Hz floor, 8kHz low-pass, LUFS targets), but never mentions a shared library module those seven scripts import from.
As written, each script is the most likely place to reimplement that shared logic independently, which is precisely the kind of duplicated, low-cohesion code the brief's "Code Quality" section asks the project to avoid: "proper componentization... minimal coupling, high cohesion."

Failure mode: a future change to the shared partial ratios, or a psychoacoustic guideline correction such as tightening the low-pass cutoff, requires editing seven files instead of one, and it is easy for one script's copy of the normalization or envelope code to drift from the other six without a test catching it, since the CI check only verifies each script's output against its own committed WAV, not that the seven scripts agree with each other on shared constants.

Resolution: extract a shared `synth.py` (partial generation, envelope, low-pass, LUFS normalization) that all seven `generate_<name>.py` scripts import, leaving each script responsible only for its own pitch contour, note count, and duration parameters.

### 6. iOS AVAudioSession category conflict between notification chimes and an active call is unaddressed

Target: "the in-app player uses the `.ambient` `AVAudioSession` category so notification sounds respect the physical silent switch."

Weakness: `.ambient` is a real, correct choice for a standalone notification chime, but the report never considers what happens when a DM or mention notification sound needs to play while a LiveKit/WebRTC voice or video call is already active, which per `media.md` requires the `.playAndRecord` category the WebRTC engine and CallKit already manage for the call.
`AVAudioSession` is one shared resource per process; switching its category from underneath an already-configured call session, even briefly, is a known source of audible glitches and race conditions between whichever code last set the category.

Failure mode: a message notification chime fires while the user is mid-call, the shared audio plugin reconfigures the session to `.ambient` to play it, and the in-progress call audio glitches, drops a frame, or the WebRTC engine's own session observer fights the plugin's category change, producing an audible artifact in a live call, a materially worse outcome than the notification sound itself.

Resolution: define an explicit precedence rule for notification playback while a call session is active, most simply suppressing or deferring the in-app chime whenever `.playAndRecord` is the active category rather than switching categories underneath a live call.

### 7. Android channel-sound update cadence and user-side overrides are not weighed against the iOS path

Target: "Channel IDs must be versioned from day one (`channel_message_v1`)," contrasted with the iOS background-sound path.

Weakness: the report gives Android an explicit mitigation for updating a background sound on existing installs, channel versioning, but never states the equivalent constraint on iOS: a bundled APNs sound file only changes for a user once they install an app update that ships the new file and Apple finishes review, which can take days to reach the full install base, unlike Android's per-channel-version approach which the report treats as solved.
Separately, each Android notification channel is independently visible and user-editable in system settings, meaning a user can silence or change any one of the seven sounds' channels without the app knowing, which works against the report's framing of the seven-sound family as something "users learn quickly" as a fixed, coherent set.

Failure mode: a post-launch sound revision (fixing a synthesis artifact, adjusting a loudness target) reaches Android users on their next app install via a new channel version, but reaches iOS users only after full App Store review propagation, an asymmetry the report never states, so a "fixed" sound is inconsistently rolled out across platforms with no one having planned for the gap.

Resolution: state the iOS release-cadence coupling for background sound updates explicitly alongside the Android channel-versioning mitigation, and decide whether sound revisions are batched with app releases specifically to avoid a long platform-inconsistency window.

### 8. No debounce or coalescing policy for rapid successive notification sounds outside the join/leave case

Target: the report's "A concern worth flagging" section, which addresses member join/leave fatigue but not ordinary message bursts.

Weakness: the report correctly identifies that join/leave sounds break down at scale and proposes a default-off threshold, but the same failure mode applies to ordinary messages: a small group DM receiving a rapid burst of messages, or a bulk operation such as a channel import, would trigger the direct-message or group-message chime once per message with no stated coalescing, debounce, or rate-limit policy at the client's sound-trigger point.

Failure mode: five people typing in quick succession in an active DM plays five chimes in two seconds, which is exactly the "quiet, pleasant, professional" goal failing in practice, just from ordinary usage rather than the join/leave case the report singles out.

Resolution: extend the join/leave mitigation's logic to a general client-side notification-sound coalescing policy, for example suppressing repeat chimes for the same conversation within a short window while the conversation is already visibly active.

## Minor findings

### 9. PipeWire stream lifecycle on Linux is unaddressed against the brief's idle-resource budgets

Target: "played directly through PipeWire rather than relying on `notify-send` or desktop sound themes."

Weakness: the report never states whether the shared plugin keeps a PipeWire client stream open continuously for low playback latency, or opens and tears one down per notification, a real tradeoff between idle memory/CPU footprint and per-sound playback latency that `performance.md` cares about explicitly with its near-zero idle CPU and sub-200MB idle memory targets for the Linux client.

Failure mode: a persistent-stream implementation adds always-on idle resource cost the performance report would flag in its CI budget gates, discovered only after the fact rather than decided up front.

Resolution: state the intended PipeWire connection lifecycle explicitly and measure its idle-state cost alongside the other Linux client budgets already tracked in `performance.md`.

### 10. pyloudnorm's supply-chain posture is not discussed against the project's own dependency-scanning discipline

Target: the CI-only `pyloudnorm` dependency in the synthesis pipeline.

Weakness: `security.md` commits the project to pinned versions, lockfiles, and CI vulnerability scanning across its runtime dependencies, but the audio report's CI-only Python dependency is not mentioned in that context, and pyloudnorm itself is a small, low-activity, largely single-maintainer library.

Failure mode: the risk is low since this is a build-time-only dependency with no runtime exposure, but an unmaintained pyloudnorm eventually blocking a Python version bump in the CI regeneration job is a plausible multi-year maintenance friction the report does not acknowledge at all.

Resolution: note the CI-only Python toolchain (numpy, pyloudnorm) in whatever dependency-scanning and update policy the project adopts elsewhere, even though it never ships to users.

### 11. No accessibility consideration for deaf or hard-of-hearing users

Target: the report's scope as a whole, which treats "distinguishable by sound" as the complete accessibility story.

Weakness: `flutter-client.md` and the brief's own UX section call out accessibility as a first-class concern for the client generally, but audio.md never connects the notification-sound design to any non-auditory fallback, such as ensuring every sound-carried distinction (urgency, event type) also has a visual or haptic equivalent for users who cannot rely on the sound family at all.

Failure mode: a deaf or hard-of-hearing user gets no benefit from the seven-sound family's careful pitch-contour and duration distinctions, and the report gives no signal that this was considered and intentionally deferred versus simply not considered.

Resolution: add a short note cross-referencing the client's visual/haptic notification treatment so the sound design is explicitly framed as one channel among several, not the sole signal for any event type.

## Closing note

The report's own domain, synthesis, timbre, psychoacoustics, is carefully reasoned and internally consistent.
Its failures are at the boundary with subsystems it did not read closely enough: the push relay's encrypted, coarse-kind payload design in `networking-relay.md` and `security.md` directly contradicts the "referenced by filename in the payload" background-sound plan, and CallKit's ownership of the incoming-call UX in `media.md` and `appstore.md` leaves the most complex sound in the family unscoped on the brief's top-priority platform.
Both are the kind of cross-report reconciliation gap that is cheap to fix now, before any generator script or platform integration code exists, and expensive to discover later in iOS QA.
