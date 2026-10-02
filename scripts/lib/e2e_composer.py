# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""What the composer does with what is typed: list keys, and :shortcodes:.

Both read the field's own text back out of the browser rather than a rendered
transcript, since the claim is about what the composer holds before anything is
sent. The one thing sent is the shortcode message, to prove the server stores
the glyph and never the colons.

On a wide window Enter sends, so a list's "Enter" is Shift+Enter here; that is
the key the desktop composer binds to a list-aware newline
(`composer_extras.dart`). A soft keyboard has no Shift+Enter, and no Tab either,
which is why docs/design/composer-list-keys.md says phones cannot indent.
"""
import time
import urllib.error

import e2e_input as I
import e2e_labels as L

# Written as an escape so no emoji glyph sits in a source file.
BUG = "\U0001F41B"


def _open_empty_composer(client, channel):
    client.click(channel)
    client.wait_for(L.COMPOSER)
    client.type_into(L.COMPOSER, "x")
    I.clear_field(client)
    assert I.focused_value(client) == "", "the composer would not clear"


def _insert(client, text):
    client.send("Input.insertText", {"text": text})
    time.sleep(0.3)


def list_keys_indent_outdent_and_end(client, channel):
    """Tab nests an item, Shift+Tab undoes it, an empty item ends the list."""
    _open_empty_composer(client, channel)
    _insert(client, "- one")
    I.press(client, "Enter", shift=True)
    assert I.focused_value(client) == "- one\n- ", \
        f"a new item was not started: {I.focused_value(client)!r}"
    _insert(client, "two")

    I.press(client, "Tab")
    assert I.focused_value(client) == "- one\n  - two", \
        f"Tab did not indent the item: {I.focused_value(client)!r}"
    I.press(client, "Tab", shift=True)
    assert I.focused_value(client) == "- one\n- two", \
        f"Shift+Tab did not outdent it: {I.focused_value(client)!r}"
    print("  Tab indented the item a level and Shift+Tab brought it back")

    I.press(client, "Enter", shift=True)
    I.press(client, "Enter", shift=True)
    assert I.focused_value(client) == "- one\n- two\n", \
        f"an empty item did not end the list: {I.focused_value(client)!r}"
    print("  Enter on an empty item removed its marker and ended the list")
    client.shot("composer-list")
    I.clear_field(client)


def a_typed_shortcode_becomes_its_emoji(client, channel, api):
    """`:bug:` turns into the glyph as the closing colon lands, and is sent so.

    Typed a character at a time, since that is when the conversion runs: a
    whole string inserted at once is a paste, which is left alone.
    """
    _open_empty_composer(client, channel)
    for char in "caught a :bug:":
        _insert(client, char)
    typed = I.focused_value(client)
    assert typed == f"caught a {BUG}", \
        f"the shortcode was not converted: {typed!r}"
    client.click(L.SEND, settle=2)
    stored = api.message_with(api.channel_named(channel)["id"], BUG)
    assert ":bug:" not in stored["content"], \
        f"the server holds the colons, not the glyph: {stored['content']!r}"
    print("  typing :bug: left the glyph in the field, and the server "
          "stored the glyph")


def a_custom_emoji_cannot_take_a_standard_name(api, picture):
    """A custom emoji named like a standard shortcode is refused with 409.

    A free name is accepted in the same breath, so the refusal is about the
    name and not about the image or the caller's permission.
    """
    with open(picture, "rb") as fh:
        image = fh.read()
    try:
        api.call("POST", "/emoji?name=bug", raw=image, content_type="image/png")
    except urllib.error.HTTPError as err:
        assert err.code == 409, f"expected 409, got {err.code}"
    else:
        raise AssertionError("a custom emoji named bug was accepted")
    print("  a custom emoji named like :bug: was refused with 409")

    created = api.call("POST", "/emoji?name=e2e_blob", raw=image,
                       content_type="image/png")
    try:
        assert created["name"] == "e2e_blob", created
        print("  while a name no standard emoji uses was accepted")
    finally:
        api.call("DELETE", f"/emoji/{created['id']}")
