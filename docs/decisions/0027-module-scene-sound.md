# 0027 - Module scene sound

Status: accepted
Date: 2026-09-16

## The ask

The owner wants modules to be able to make sound, "to allow for more creativity", with a BeepBox-style music maker named as the eventual goal.
This record covers the foundation only: a scene op a module can emit notes through, and the playback behind it.
It does not build a music module, and it does not build the music maker itself.

## What a module actually emits

A module never ships a sample, a waveform, or a codec's worth of audio bytes.
It emits a `notes` scene op: a list of `{f, t, d}` triples (frequency, start time, duration), the same three numbers `assets/audio/synth.py`'s `Note` carries, minus `gain`.
slim renders the notes and plays the result.
This keeps a module's sound to the same shape as its drawing ops: small, declarative, and something slim itself is the sole renderer of.

## One timbre, not two

slim already has a synthesiser and a sound identity: `assets/audio/synth.py` renders the seven notification chimes from three fixed partials (`_PARTIALS`) and a fixed envelope, on a pentatonic ladder chosen so any two chimes landing together still agree.
`client/packages/app/lib/src/audio/scene_synth.dart` is a faithful Dart port of that file's `bell` and `render` - same partials, same envelope shape, same 48kHz sample rate - so a module's sound and slim's own notification sounds share one voice.
A module could in principle ask for any pitch and rhythm within the ceilings below; what it cannot do is ask for a different timbre, because there isn't a second one to ask for.

The Python file's loudness work (`_k_weighted`, `loudness`, `normalise`, `pyloudnorm`) is deliberately not ported.
That machinery levels seven known clips against each other at build time using a whole-clip analysis and an offline library; a module's cue is rendered on a device in response to a tap, with no fixed reference set to level against, so the comparison the LUFS work makes doesn't apply here.
The port stops at the safety clip `synth.write_wav` already does regardless of normalisation (clamp to [-1, 1] before quantising to 16-bit), which is an overflow guard, not a loudness decision.

## The abuse case, and the two-part defence

Sound triggered by a message is not like a drawing on a message: everyone who can post to a channel can make every viewer's device make noise.
A drawing that renders wrong is silently ignorable; a sound that plays wrong is not.
Two independent controls hold this, and either one alone is enough to stop the abuse:

1. **Never plays without the viewer's own interaction.** `ModuleSceneView` only calls its `onNotes` hook from the success path of an action *this* view itself sent - a tap, a drag, a control press, or a step this view's own "play" loop asked for after the viewer pressed play. A scene's first paint never triggers it, and neither does a scene update that arrived because another viewer acted on a shared one (`_isOwnWork` already exists to tell the two apart, for the unrelated reason of not restarting play on your own broadcast echo - the same check is what makes this safe). A module cannot make a viewer's device play a sound by posting a message; it can only make sound as the direct answer to that one viewer's own tap.
2. **A switch a person can find.** `moduleSoundSettingsProvider` is a plain per-device on/off, wired into the Notifications section the same way `messageSoundSettingsProvider` already is (`personal_status_sections.dart`), because that is where "does my device make noise" preferences already live and where someone would look for this one. Default on, matching the existing message-sound default, since the feature does nothing until a module actually uses it.

## The ceilings

Enforced in `NotesOp`'s own constructor, before anything downstream (the synthesiser, the player) ever sees an unbounded list:

- `maxNotes = 32` - a module scene is a small UI, not a sequencer; more notes than this is a wall of tone, and it bounds the arithmetic one op can ask the synthesiser to do.
- `maxNoteSeconds = 3.0` - rules out "hold a tone for an hour" at the single-note level.
- `maxSceneSeconds = 8.0` - bounds how late into a cue a note may start, kept separate from `maxNoteSeconds` so a module cannot stretch a whole cue's length by starting one note late rather than by holding it.
- `minFrequencyHz = 20.0` / `maxFrequencyHz = 7800.0` - below 20Hz a "note" is a sub-bass thump, not a pitch; above 7800Hz the synthesiser's own highest partial (3.05x the fundamental, from `_PARTIALS`) would sit past the 24kHz Nyquist limit at 48kHz and alias back down as noise.

A note outside these ranges is clamped, not rejected, and an op past `maxNotes` is truncated rather than thrown away whole - the same "skip or clamp what is bad" treatment a malformed cell or a bad hex colour already gets elsewhere in the scene contract.

Playback itself cannot queue faster than it plays either: `AudioPlayersModuleSoundPlayer` stops whatever is already sounding before starting the next render, so a fast run of actions replaces the previous cue rather than layering sound on top of it.

## Where synthesis runs

Rendering a cue is arithmetic over tens of thousands of samples (up to `maxNotes` notes, each up to `maxNoteSeconds` long, at 48kHz).
`AudioPlayersModuleSoundPlayer.playNotes` runs it through Flutter's `compute()`, off the UI isolate, for the same reason module command execution is already an async round trip rather than inline work: nothing about a module's output, drawn or heard, should be able to cost a frame.

## Additive, per decision 0022

`notes` is a new scene op inside `scene/1`, which decision 0022 already states is additive: an op an older client does not recognise is skipped, and the rest of the scene renders normally.
`module_scene_test.dart` proves this holds for `notes` the same way it already does for `rect`, `circle`, `line` and `text`.

## What this does not build

- No music-maker module. No sequencer UI, no track/pattern editor, no BeepBox-alike anything.
- No new capability, extension-point kind, or wire frame. `notes` is a scene op like the other five; it needs none of decision 0022's other growth seams.
- No per-scene or per-module volume, instrument, or pan control beyond the three fields above.
