# Wording table

One word for each kind of action and name, so two panes never say the same thing two ways.
The strings live in `client/packages/app/lib/src/action_labels.dart`; a gate in `test/wording_gate_test.dart` fails if a retired spelling returns.

## Verbs

- Create for a server-side object: Create channel, Create category, Create role, Create invite, Create emoji, Create bot, Create webhook, Create a reset code.
- Add reaction for a reaction, everywhere (hover toolbar, context menu, picker). A reaction is attached to a message, not created.
- Remove for taking someone out of the Space: "Remove from Space...", the "Removed members" pane and the "Remove members" permission. Never kick.
- Ban stays its own word, because it is a different action.

## Names

- Space is the one word for a deployment inside the app. The sign-in screen's Server field is the address of the thing being connected to and is a separate owner decision.
- Settings > Media and cache is this device's media and cache options.
- Space settings > Operations > Retention and limits is the Space's message retention and canvas cap.
- The group heading in Space settings is Operations, not Server.

## Patterns

- One empty state for a settings or admin list: `SettingsEmpty`, a sentence in a card at the top left. Inside an existing card use `SettingsEmptyLine`.
- One create button per pane, in the title bar when the pane has one. A list does not repeat it.
- A section title never repeats its pane title.
- Sibling destructive buttons sit at the card's own inner padding, with no extra wrapper.
