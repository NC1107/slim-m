# Every screen, reviewed by a panel

A per-screen improvement report over the whole rendered UI.
Read `docs/reports/screen-inventory.md` first if you want the map of what exists; this is the judgement pass on top of it.

## How this was produced

`scripts/ui-capture.sh` renders the real app through four harnesses and writes **509 images covering 249 distinct screen states** into `build/ui-capture/images/`, grouped into four categories: routed screens, overlays (sheets, dialogs, menus, popovers), the assembled canvas, and the canvas painters on their own.
Every routed screen is rendered at several viewports and in all themes, and the capture brackets the exact widths where a layout changes shape (467/468, 599/600, 799/800, 899/900, 999/1000) so a breakpoint is looked at from both sides rather than assumed.

Each area then went to a panel of three specialists who looked at the same images independently:

- **frontend** - layout at every viewport, design-system conformance, whether each state renders as itself, widget-structure smells in the source behind the screen
- **ux and accessibility** - copy, hierarchy, whether a state is a dead end, cues carried by colour alone, touch targets
- **backend and contract** - whether what a screen claims matches what the server actually does, checked against the handler and the schema rather than the label

A finding earns its place only if it names a concrete improvement, cites the image it was seen in, and points at a file. "Nothing to change here" is recorded as a verdict rather than padded out.

## Areas

| Area | Screens | Report |
| --- | --- | --- |
| Onboarding and server connection | onboarding, sign-in, invite and manual-server dialogs, the nine submit failures, TOFU and identity, probe notices | [onboarding.md](onboarding.md) |
| Shell and messaging | channel, thread, DM, rail states, transcript empty/offline/catching-up, no-channel-selected | [shell.md](shell.md) |
| Settings and administration | personal settings, Space settings and its access tiers, roles, invites, overwrites, categories, emoji, reports, analytics, removed members, debug log | [settings.md](settings.md) |
| Voice | join preview, connecting, in-call and its variants, rejoin, switch prompt, who-is-here, DM call | [voice.md](voice.md) |
| Canvas | the pane, the combined call-and-canvas surface, tools, errors, activity log, and the painters | [canvas.md](canvas.md) |
| Overlays | sheets, pickers, confirmations, context menus, the command palette | [overlays.md](overlays.md) |
| Moderation and safety | member popovers and their permission tiers, report cards, safety notices, blocked-DM notices | [moderation.md](moderation.md) |

## Reading a finding

Severity is about what it costs the person using the product, not how hard it is to fix.

- **high** - the screen misleads, strands, or is unusable at a viewport somebody really has
- **medium** - the screen works and something about it is worse than it needs to be
- **low** - polish, consistency, or a thing worth knowing before the next change here

Anything marked **suspected** was reasoned from the image alone and not confirmed against source; treat it as a lead rather than a finding.
