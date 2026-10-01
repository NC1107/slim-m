# 0053 - custom emoji names, search, and what a typed shortcode does

Status: accepted, 2026-10-01.

## The report

The owner, about custom emoji:

> "emojis list get long, need search functionality, and duplicate checking if not already there to ensure we dont make two :bugs: for example."
> "emojis dont render after I type one out like :bug: in my input box"

## What was already true

The server refused a second custom emoji with the same normalised name (409), and the new-emoji card said "Already taken." for a name in the loaded list.
The reaction picker already searched the whole catalog, the Space emoji first.
The settings list and the phone sheet that lists the Space's own emoji had no search.
A message renders only custom `:name:` tokens as images, so a typed `:bug:` stayed literal text in the field and in the sent message unless it was custom.

## What changed

- **Search.** The settings list and the touch picker sheet each get one search field above the list.
  The match is a case-insensitive substring on the name with typed colons ignored, the same rule as the picker.
  An empty result says so with the query in the sentence.
- **A custom name may not be a standard shortcode.**
  A custom `:bug:` would hide the standard bug emoji from everyone, since a name resolves to the Space's image first.
  The server refuses such a name with 409 on upload, bulk upload and the CLI import.
  The list lives in `crates/slimm-server/src/emoji/builtin_names.txt`, generated from the client's `emojis` package short names reduced to what the normaliser keeps, and a client test holds the client's own set equal to it.
  Emoji that already exist under such a name are left alone and keep winning the name.
- **A taken name shows its owner.**
  The card names the existing emoji and draws it, before any request.
- **Identical image bytes are reported, not blocked.**
  The upload response may carry `same_image_as`, the name of the oldest other emoji with the same bytes.
  The card says so and offers "Use :x: instead", which removes the new one, or "Keep both".
- **A typed shortcode.**
  When the closing colon completes a standard `:name:` that follows whitespace or starts the text, the field replaces it with the glyph.
  This is what the autocomplete list already inserted for a standard emoji, so a sent message holds the glyph.
  Backspace straight after the conversion restores the typed `:name:` and it does not convert again until another colon is typed.
  Nothing converts inside an inline code span or a fenced block, including a fence that is still open.
  A Space emoji keeps its `:name:` text, since a plain text field cannot draw an image inside the text.
  A row above the field previews each Space emoji the draft will render, read with the same parser a message uses.
  The Space emoji wins a name over a standard one, as it does when a message renders.

## Not decided here

An inline chip drawn inside the text field is not built.
It needs a text field that can hold widgets without breaking caret and selection offsets, which the stock one cannot do.
