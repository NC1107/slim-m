# 0013: One container system for settings and administration

Date: 2026-08-10
Status: accepted

## Why this exists

The owner, on the settings surface: "space settings and personal settings look very difficult UI wise, we need to decide on a container for each of these UI components and cleanup this mess", and then "setting ui on space and personal really looks like shit, so overhaul it".

`docs/reports/screen-review/settings.md` had reviewed this same area a day earlier and rated personal settings "clean across all three lenses, no findings".
Both are correct, and the gap between them is the finding.
That review checked each screen for correctness in isolation: does its copy say what is true, does its gating match the server, does it handle its own empty and error states.
Nobody checked whether the screens use a consistent container idiom *with each other*.
A per-screen review is structurally incapable of seeing that, because every one of the six idioms below is defensible on the screen it appears on.
It is only when you cross from one screen to the next that the surface reads as unfinished.

## The inventory

Six different ways to express "a group of related settings", across twelve screens that sit one tap apart from each other.

1. **`SettingsSectionCard`**: a prominent header *outside* a bordered card holding rows.
   Used by every personal settings pane and by `SpaceSettingsSection`.
2. **`AppCard(title:)`**: a small uppercase micro-label header *inside* the card, with its own hairline under it.
   Used by `channel_overwrites_screen` ("CHANNEL", "ROLE"), `report_card` ("REPORTED USER"), `analytics_charts`, `emoji_upload_card`, `invites_screen`'s create form.
   This is the same semantic job as (1) - naming a group of rows - rendered completely differently.
3. **A bare `AppCard` per list item**, each hand-rolling `Row(leading?, Expanded(Column(title, subtitle...)), actions)` with an `AppErrorState` appended.
   Five independent copies: `roles_screen`, `invites_screen`, `emoji_screen`, `removed_members_screen`, `categories_screen`.
   A list of three roles is three separate bordered boxes floating with gaps, where the same three items in Space settings would be three rows inside one box.
4. **`SettingsGroupHeader` plus loose uncontained rows.**
   `app_info_section` alone: the one personal-settings section with no bordered box at all, sitting directly on the pane background beside siblings that all have one.
5. **A local `_SectionHeader` and no container whatsoever.**
   `voice_settings_screen`, for all five of its sections. The local header duplicated `SettingsSectionHeader`'s look while omitting its `Semantics(header: true)`, so none of those headings were announced as headings.
6. **`ListView.separated` with a raw Material `Divider` and no card.**
   `debug_log_screen`, which also built its own `Scaffold`/`AppBar` rather than the shared frame, losing the named back-button tooltip every sibling carries.

Three different horizontal content insets follow from that: 32 for personal and Space settings (the screen frame's 16, plus another 16 `SettingsSectionCard` added on top), 16 for every admin screen, and 0 for the debug log.
Sibling screens indenting their content by three different amounts is the specific thing that reads as "difficult" when you move between them, and it is measurable in the capture PNGs rather than a matter of taste.

Two smaller inventories in the same area:

- **Three shapes for a toggle row.** `AppListRow(trailing: AppToggle(...))` in `appearance_settings_section`, and a hand-rolled `Padding(Row(Expanded(Text), AppToggle))` in `voice_settings_screen` (twice) and `personal_status_sections`.
- **Two competing scaffolds**, which is correct and stays: `SettingsScreenScaffold` (a single scrolling screen) and `SettingsPanesScaffold` (a nav beside a pane). Personal settings genuinely is a different navigation shape from a single admin screen. What was wrong is that the two did not agree on anything *below* the frame.

## The decision

**A settings or administration screen body is a stack of `SettingsSectionCard`s. Nothing else is a container.**

The vocabulary, in full. Each entry names when to reach for it, so a future contributor picks rather than invents.

| Component | Use it for |
|---|---|
| `SettingsSectionCard` | Any group of related settings or items. Title outside, bordered card inside. Optional `description`, optional header `action`. |
| `AppListRow` | A row that navigates somewhere or opens a picker. Single-line by design. |
| `SettingsSelectRow` | A row stating its current value and opening a sheet to change it. |
| `SettingsToggleRow` | A setting you turn on or off. Wraps its label. |
| `SettingsEntityRow` | One administered item in a list: a role, an invite, an emoji, a removed member. Headline, optional badge, caption lines, trailing actions, its own inline error slot. |
| `SettingsNotice` | A surface with nothing to show, and the reason why. |
| `SettingsAbsentValue` | One optional field that has no value, inline where the value would be. |

And the rule that keeps the insets from drifting apart again: **horizontal inset is owned by the screen frame, never by a section.**
`SettingsScreenScaffold` and `SettingsPanesScaffold`'s pane body each already pad by `AppSpacing.s16`. `SettingsSectionCard` used to add another 16 on top, which is where the 32-versus-16 split came from. It adds none now.

## What was rejected

**Converting the admin lists to `AppListRow`.**
The obvious unification, and it loses information. `AppListRow` is deliberately single-line and fixed-height, and ellipsizes its label to hold that, because a rail of channels needs an even rhythm. An invite carries a code, a state badge, a uses-and-expiry line and a role grant: four pieces over three lines. `SettingsEntityRow` is a sibling of `AppListRow`, not a variant of it, and the two are kept apart on exactly that axis.

**Making every toggle an `AppListRow(trailing: AppToggle(...))`.**
Same failure, smaller. Three of these settings are whole sentences - "Play a sound when someone joins or leaves a call" - which fit a desktop pane and do not fit beside a toggle at phone width. Truncating the middle of a sentence that explains what a switch does is worse than a row of uneven height, so `SettingsToggleRow` wraps.

**Putting the new components in the design system.**
They are compositions of design-system primitives expressing *this app's* settings conventions, not primitives in their own right. `SettingsScreenScaffold`'s own library doc already draws this line for itself, and this follows it: a component library has no business knowing that an administered entity carries an inline failure banner. `AppCard`, `AppBadge`, `AppErrorState` and `AppToggle` stay where they are and these compose them.

**Retiring `AppCard(title:)`.**
It stays in the design system and is still right for a genuinely nested panel - a floating canvas window, a chart card. What changed is that settings does not use it, because in settings it was competing with `SettingsSectionCard` for the same job.

**Converting the Space settings section gate to per-channel permissions.**
Decision 0011 explicitly decided the outer Space-settings section gate stays on base permissions, and reopening that here would contradict a decision two days old for a cosmetic reason. The "Channel permissions" row's own gate had already been widened to include a channel-scoped `MANAGE_ROLES` (`canManageRolesAnywhere`). The residual is the reverse case, a caller holding base `MANAGE_ROLES` who is denied it in one channel by an overwrite: they can still open the screen, pick that channel and be refused on submit. That is disclosed in copy rather than pre-computed, matching the gate-then-surface pattern the review named as this area's most consistent strength.

## The rule a future contributor follows

Before adding a container to a settings or admin screen, pick from the table above.
If none of them fits, that is a finding worth writing down rather than a licence to hand-roll a sixth idiom: say what does not fit and extend the vocabulary deliberately.

The specific mistakes that produced this mess, so they are recognisable next time:

- Reaching for `AppCard` directly instead of `SettingsSectionCard`, because `AppCard` is what the design system exports and is one import closer.
- Writing a local `_SectionHeader` because the shared one was in a file you were not already importing. That is how `voice_settings_screen` lost its heading semantics.
- Adding padding to a section because it looked too tight, without checking whether the frame already added some.
- Hand-rolling a row shape for one screen. Five screens did that independently and all five agreed by luck on the caption style, which is not the same as agreeing structurally.

## What this does not settle

Whether `SettingsPanesScaffold` and `SettingsScreenScaffold` should eventually be one thing.
They are genuinely different navigation shapes today and the split is deliberate; a single settings surface that adapts between "one scroll" and "nav plus pane" is a larger question than a container vocabulary and nobody has asked for it.

Whether the six-idiom drift would have been caught by a mechanical gate.
A gate on "no bare `AppCard` under `screens/admin/`" would have caught idiom 3 and none of the others, and would have false-positived on the legitimate chart cards. The honest answer is that this class of drift is caught by looking at the rendered screens side by side, which is what `scripts/ui-capture.sh` is for, and it went uncaught because nobody had looked at the whole set in one sitting.
