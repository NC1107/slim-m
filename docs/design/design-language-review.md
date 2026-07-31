# Design Language Plan: Adversarial Review

Target document: `docs/design/design-language.md` (moved out of `docs/research/` on 2026-07-26; this review predates the move).
Cross-checked against `docs/BRIEF.md`, `docs/research/flutter-client.md`, `docs/research/voice-canvas.md`, `docs/research/performance.md`, `docs/research/ux.md`, `docs/research/appstore.md`, `docs/research/oss.md`, and the sibling review `docs/research/flutter-client-review.md`.
Every color-contrast figure below is computed directly from the hex values in `design-language.md` using the standard WCAG relative-luminance and contrast-ratio formulas, not estimated by eye.

Severity key: critical findings would force a redesign of the plan as written.
Major findings are real defects that should block sign-off until addressed.
Minor findings are worth fixing but low risk either way.

## Critical findings

### 1. The border-first elevation system is close to invisible, by the report's own numbers

`design-language.md` makes "border-first elevation" the foundation of the entire spacing and depth system: "a 1px hairline is the default separator," chosen explicitly over shadows for both performance and identity reasons (line 60-61).
The report also claims "every foreground/background pair is checked against WCAG 2.1 AA... at authoring time" (line 33).
Computing the actual contrast of `border.subtle` against the surface it separates gives, in every one of the three theme variants the report defines: light, 1.20:1 (against `surface.base`) and 1.28:1 (against `surface.raised`); dark, 1.31:1 and 1.19:1; true black, 1.35:1 and 1.20:1.
All six numbers sit far below the 3:1 WCAG non-text contrast threshold for UI component boundaries, and more importantly, they sit far below ordinary human perceptibility: a border this close in lightness to its background will not read as a visible line on most displays, regardless of which accessibility standard applies to it.
Since `border.subtle` is the only border-color role the token table defines, and radius step 6 is explicitly assigned to "buttons, inputs" (line 59), this is very likely the same token drawing the boundary around interactive form controls, not just decorative dividers.
This is a critical finding because it cannot be patched by adjusting a downstream value.
The whole rationale in the "Spacing, Radius, and Elevation" section for rejecting shadows was that hairline borders would do the separation job at lower render cost.
If the specified border color cannot actually be seen, the system has no functioning separator at all, and fixing it means either darkening the border enough to undermine the "hairline, understated" look the report is optimizing for, or reintroducing shadows or a stronger background-tint depth cue, which contradicts the stated performance and identity rationale for choosing border-first in the first place.
Either path is a redesign of this section, not a token edit.

### 2. The accent color fails the report's own declared body-text contrast bar, in light mode specifically

The report states the accent exists "where color carries meaning" and sets it as the one signature brand hue (line 8, line 27), then separately claims "every foreground/background pair is checked against WCAG 2.1 AA (4.5:1 body text...) at authoring time" (line 33).
Computed contrast for `accent.default` light (`#2B8A83`) is 3.90:1 against `surface.base` (`#F7F8F9`) and 4.15:1 against `surface.raised` (`#FFFFFF`), both below the 4.5:1 body-text threshold the report itself names.
Dark mode is fine: `accent.default` dark (`#4FBDB4`) measures 7.78:1 against `surface.base` dark, comfortably above 4.5:1.
That asymmetry is the tell: the report correctly hand-tuned dark values independently rather than deriving them by inversion (line 31), but nobody re-checked the light accent against the same body-text bar once the dark value was fixed, so the two themes were not actually held to a consistent standard despite the claim that they were.
Any body-sized use of the accent in light mode, an inline link, an `@mention`, an unread-count label, is out of spec today.
This is critical, not major, because the accent is not an incidental token.
It is the one hue the entire "Overall direction" section is built around, it is already baked into the marketing-facing "Design Brief Prompt" at the end of the same document (line 115), and the report has already decided the website gets "more accent latitude" than the product (line 32), meaning a retune of this primitive propagates into at least two other decisions that currently treat `#2B8A83` as locked.

### 3. The report contradicts its own declared accessibility standard inside the same document

The typography section states: "Text respects OS text-scale up to 130 percent, verified by golden tests already planned in `flutter-client.md`" (line 52).
The same document's closing section states the opposite ambition: "I am treating this as a gap to close, not defer, and setting WCAG 2.1 AA as the explicit target" (line 93).
WCAG 2.1 AA includes Success Criterion 1.4.4, Resize Text, which requires content and functionality to remain usable with text scaled up to 200 percent, not 130 percent.
This is not merely a cross-document inconsistency: `flutter-client-review.md` already flagged that `ux.md` separately commits to "font scaling to 200 percent" (its line 55) while `design-language.md` says 130 percent, and treated it as a documentation-drift problem between three reports.
The sharper problem is internal to `design-language.md` alone: the same document states a 130 percent implementation ceiling in one section and cites WCAG 2.1 AA, a standard whose own text requires 200 percent, as its explicit accessibility target in another.
Closing that gap for real is not a number change.
The layout the "Design Brief Prompt" describes is a fixed three-pane arrangement (sidebar, channel and message list, member list) at the spacing and radius tokens already specified; reaching genuine 200 percent text-scale support in that layout requires reflow, truncation, and breakpoint decisions the report never raises, which is layout-architecture work, not a token-table edit.

## Major findings

### 4. True black triples the theme-QA surface for a benefit that does not apply to the plan's primary desktop target

`flutter-client.md` names light, dark, and true black as the three theme variants (its line 51), and `design-language.md` supplies distinct hand-tuned hex values for all three (the color table, lines 20-27).
True black's actual benefit, OLED per-pixel power savings, applies to phone displays, not to Fedora Linux desktop monitors, which the brief names as a primary testing target and which are never OLED.
`flutter-client.md`'s own testing-pyramid section commits golden-test coverage only to "light and dark themes and at least two viewport widths" (its line 87); true black is never named there at all.
That leaves two bad options, neither of which the report resolves: true black ships with no golden-test protection, silently contradicting the "every dark value above is hand-tuned instead" promise design-language.md makes for it (line 31), since a hand-tuned value nobody visually regression-tests can drift unnoticed, or golden coverage must expand to a third variant that was never budgeted for in the testing plan, on top of the font-scale and viewport dimensions already flagged as a combinatorial and flakiness risk in `flutter-client-review.md` finding 11.
Either way, this is real engineering cost paid mostly for a platform (Linux desktop) that gets none of the benefit the token was introduced for.

### 5. Typography locks a typeface with no stated non-Latin script or emoji strategy

The typography section evaluates IBM Plex Sans purely on character and binary size versus Inter (line 38) and never addresses script coverage.
IBM Plex Sans's variable font covers Latin, Cyrillic, and Greek; it does not cover Arabic, Hebrew, Devanagari, Thai, or CJK, and Plex ships those as separate, differently-designed family files (Plex Arabic, Plex Devanagari, and so on), not additional weights of the same variable font.
No color emoji glyphs exist in Plex at all, on any platform.
For a self-hostable, openly licensed messaging platform that the OSS report explicitly wants to be internationally adoptable (`oss.md`'s AGPL-for-services, Apache-for-client framing assumes a global self-hosting audience), this is a real gap: every non-Latin-script deployment either falls back silently to a mismatched system font, breaking the weight and baseline consistency the typography section is built around, or the project has to bundle additional script-specific Plex families later, which was never counted against the binary-size claim in finding 6 below.
Emoji rendering falls back to the OS emoji font on every platform regardless of typeface choice, which is normal, but the report does not say so, leaving it to be discovered during implementation rather than decided now.

### 6. The "small win against the binary-size budget" claim for the variable font is asserted, not measured

Line 38 frames one bundled IBM Plex Sans variable file as "a small win against the client's binary-size budget."
`performance.md` sets that budget as a hard, CI-enforced number: under 60MB compressed for iOS, under 80MB for the Linux AppImage, with a 5 percent size-regression failure threshold on every PR (its section 1 and section 4).
No actual compiled asset size for the chosen Plex configuration, weight axis only versus a fuller Unicode range, is given anywhere in the report, so the claim cannot be checked against the budget it invokes.
A single variable font with a wide script range is not reliably smaller than two or three static Inter weights; it depends entirely on which glyphs are subsetted in, a decision the report never makes explicit.
Locking the typeface as a design decision before measuring the actual compiled size against a CI gate that fails builds at a 5 percent regression risks tripping that gate on the first PR that adds the font, which is an implementation-order problem this report should have flagged rather than left implicit.

### 7. The tokenized icon stroke width is not something an off-the-shelf icon font actually delivers

Line 69 specifies icons "tokenized at 16, 20, 24 (default), 32dp, 1.5px stroke at the 24dp reference," implying stroke width is a property that can be held constant, or at least deliberately varied, independent of the rendered size.
Phosphor Icons, consumed through the standard Flutter integration, ships as fixed glyph outlines per weight (regular, bold, fill, and so on), not as parametric stroke paths.
Scaling a fixed-outline glyph from a 24dp reference down to 16dp or up to 32dp changes the glyph's apparent stroke thickness proportionally along with everything else; it does not hold a literal 1.5px stroke constant, and Phosphor does not ship separate hand-tuned outlines per size to compensate.
Achieving a genuinely constant physical stroke width across four discrete size tokens would require either custom per-size glyph variants, which Phosphor does not provide, or SVG path-based icons redrawn per size, which is a materially different implementation than "drop in an icon-font package."
This undercuts the stated rationale for choosing Phosphor over a custom set in the first place: the report rejects a full custom icon set specifically to avoid "commissioning new art per feature" (line 70), but the stroke-width guarantee as written can only be delivered by exactly that kind of custom per-size work.

### 8. Canvas participant cursor colors reintroduce the color-only signaling problem the report explicitly solved elsewhere

Line 29 correctly requires status dots to carry "a distinct shape" alongside color "since state never depends on color alone."
The very next sentence assigns canvas participant cursors "their own categorical set, spaced away from the accent and status hues," with no equivalent non-color differentiator specified, no label, no pattern, nothing.
This is an internal inconsistency: the same paragraph states the color-only-signaling principle and then does not apply it to the other place in the same feature set where it clearly matters.
A color-blind participant in an active Voice Canvas session, which the brief calls one of the product's defining features, has no way to tell whose cursor is whose beyond hue, exactly the failure mode the status-dot shape rule exists to prevent.

### 9. The same cursor-color palette has no stated collision policy, and the brief's own official centralized server is where it would actually be tested

A "categorical set... spaced away from the accent and status hues" is realistically eight to twelve distinguishable hues before adjacent colors become hard to tell apart, especially under the muted, desaturated palette philosophy the rest of the report commits to.
Neither `design-language.md` nor `voice-canvas.md` caps Voice Canvas participant count, and the brief explicitly supports an "official centralized server" alongside self-hosted instances, the one deployment where a well-attended voice-and-canvas session is realistic rather than hypothetical.
Past the palette's effective ceiling, two different users get duplicate or near-duplicate cursor colors with no documented fallback, initials, name label on hover, or pattern, defeating the stated purpose of a "categorical" palette exactly where the official hosted instance would first expose the gap.

### 10. Two of the report's own six named color roles have no defined values, so the accessibility audit claim cannot be verified for them

The report names six meaning-carrying color roles across the document: `surface`, `border`, `text`, `accent`, status colors, and canvas cursor colors.
Only the first four get actual hex values in the color table (lines 20-27).
Status colors are described only as "the conventional traffic-light palette (green online, amber away, red do-not-disturb, gray offline)" (line 29) with no hex values given, and cursor colors are described only as "their own categorical set" (line 30) with no values either.
The claim that "every foreground/background pair is checked against WCAG 2.1 AA... at authoring time" (line 33) cannot be true for these two roles today, since there is nothing yet to check them against.
Combined with findings 1 and 2, which show that even the roles that do have defined values were not consistently checked, this leaves the report's central accessibility claim unverified for the majority of its own named color roles.

### 11. The Design Brief Prompt handed to an external design tool never asks for true black, undermining the report's own hand-tuning claim for it

The report insists dark-mode values must be hand-tuned per surface rather than derived by inverting light-mode lightness, and explicitly extends that discipline to true black, "every dark value above is hand-tuned instead" (line 31), covering all three columns of the color table.
The "Design Brief Prompt" at the end of the same document, meant to be submitted to an actual design tool or designer, asks only for "light and dark mode screens" in its deliverables list (line 141) and never mentions true black anywhere in the prompt text.
If this prompt is the actual production pipeline for validating hand-tuned values against real screens, as the rest of the document implies it is, true black gets no equivalent design pass.
Its values in the token table will have been produced by an engineer approximating OLED-safe darkness from the dark-mode values, not hand-tuned against real mockups the way the report claims for the other two variants.

## Minor findings

### 12. The 44 to 48dp touch-target figure is attributed to the wrong standard, and a sibling report specifies a different number for the same token

Line 93 lists "minimum 44 to 48dp touch targets" as part of "setting WCAG 2.1 AA as the explicit target."
WCAG 2.1's only target-size success criterion, 2.5.5, is Level AAA, not AA; WCAG 2.1 AA itself contains no minimum target-size requirement at all.
WCAG 2.2 later added an AA-level target-size criterion, 2.5.8, but its minimum is 24 by 24 CSS pixels, not 44 to 48.
The 44 to 48dp figures are Apple Human Interface Guidelines and Material Design conventions, not a WCAG 2.1 AA number.
This does not weaken the target itself, 44 to 48dp is a reasonable and commonly used floor, but it shows the citation meant to give the brief's vague "accessibility" bullet a concrete, verifiable standard was not itself checked against the standard's actual text, which matters given the report frames this section specifically as fixing the brief's lack of precision.
Separately, `ux.md` commits to a single fixed "48 by 48 logical-pixel minimum tap target app-wide" (its line 55), while `design-language.md` specifies a 44-to-48dp range for the same token domain; a second, smaller inconsistency worth reconciling to one number owned by one document.

### 13. Capping weight at 600 removes the strongest emphasis tool right where the report's own risk note says rendering is already weaker than expected

Line 51 caps weight at 600 and states bold 700 is unused.
The risk note in the same section separately flags that "Plex can render slightly heavier than Inter on Linux fontconfig at small sizes" (line 54), a rendering-weight risk in the opposite direction.
A chat application needs a strong emphasis step somewhere for search-term highlighting, matched `@mentions`, and unread badge counts; at the 11 to 15sp sizes the type scale specifies for micro, caption, and body tokens, the visual difference between 500 and 600 is subtle enough that relying on it as the only non-color emphasis mechanism risks reading as barely-there on exactly the platform the report already worries about for a different reason.

### 14. The Voice Canvas motion exception never states whether reduce-motion still applies to the canvas's own decorative motion

Line 78 states "all non-essential motion respects the OS reduce-motion setting, collapsing to instant state changes," immediately followed by the Voice Canvas exception permitting "more energetic motion" (line 80).
Direct-manipulation gestures, drag, pan, zoom, tracking the pointer 1:1, should legitimately stay unaffected by reduce-motion, since they are user-driven, not decorative, and the report is right to carve those out.
What is left unstated is whether the same exception also covers the canvas's own non-essential decorative motion, entrance animations for pasted objects, spring-back effects, cursor trails, as distinct from direct manipulation.
A live Voice Canvas session with several moving camera bubbles, cursors, and floating windows is exactly the kind of sustained, multi-object motion pattern that can trigger vestibular or photosensitive reactions, which is the population the reduce-motion setting exists to protect, and the report does not say whether that protection still applies inside the feature it has already decided gets to be the most visually active part of the product.

## Gaps the specialist should have raised but did not

- Whether self-hosted operators can override the accent or branding tokens per deployment. `flutter-client.md` forbids raw literals outside the generated, CI-drift-checked token file, which means the only way for a self-hosted community to express its own identity, the way the brief's own "servers/spaces" framing implies communities normally would, is to fork and recompile the client. This is never raised as a decision either way.
- What the actual measured compiled size of the chosen IBM Plex configuration is, and whether it fits inside the binary-size budget `performance.md` enforces in CI, before the typeface choice is treated as locked (see finding 6).
- Whether golden-test coverage will actually expand to include true black, and who owns updating `flutter-client.md`'s testing section to say so, since that section currently names only light and dark (see finding 4).
- What the actual hex values for status colors and canvas cursor colors are, and whether they pass the same contrast bar claimed for the rest of the palette, since neither is defined yet (see finding 10).
- Whether reduce-motion suppresses the Voice Canvas's own decorative motion, as opposed to only exempting direct-manipulation gestures from it (see finding 14).
- Which single document owns the touch-target and text-scale numbers going forward, given `design-language.md`, `ux.md`, and `flutter-client.md` currently each state a slightly different figure for at least one of the two (see findings 3 and 12, and `flutter-client-review.md` finding 11).
