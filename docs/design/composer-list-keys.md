# Composer list keys

The composer treats a line starting `-`, `*` or `N.` as a list item.
Nesting is two spaces per level and renders three levels deep (`kMaxListDepth`), for bullets and numbers, and a bullet can nest under a number and the reverse.
Indent beyond the third level renders as the third.

| Key | On a list line | Anywhere else |
| --- | --- | --- |
| Tab | One level deeper, for every list line in the selection. Stops at level three but still consumes the key. | Moves focus on, as it always did. |
| Shift+Tab | One level shallower. No-op on a top-level item, except an empty one, which loses its marker and ends the list. | Moves focus back. |
| Enter | Continues the list at the same depth. On an empty item: steps out one level, and at the top level removes the marker. | Newline. |
| Backspace | At the end of an empty item: same as Enter on an empty item. | Normal delete. |
| Escape, then Tab | Leaves the box, without editing it. | Moves focus on. |

Tab is claimed only on a list line, so a keyboard user is never trapped by plain prose.
On a list line it would be a trap, so Escape hands Tab back until the next ordinary key (modifiers do not count).
This is the same "no keyboard trap" rule `desktop-vs-mobile.md` states for overlays.
An open mention or emoji suggestion list keeps Tab as accept.
Ordered items are renumbered at the point where their depth changed; the renderer counts by position anyway, so the stored numbers only matter to the person typing.
The server stores the text unchanged, so no server-side list handling needs to agree.
Soft keyboards have no Tab key, so phones cannot indent from the composer.
