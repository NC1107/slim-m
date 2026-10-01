# 0054 - Push previews are an account choice, on by default

Status: accepted, 2026-10-01.

## The report

On iPhone every notification read "New message", for bots and people, for several members.
The preview was opt-in and stored per device.
A reinstall or a fresh sign-in makes a new device row that started at off, and most members never found the setting.

## What changed

`users.push_include_content` (migration 0097) holds the member's choice, with NULL meaning they never chose.
An account that never chose gets `DEFAULT_PUSH_PREVIEW` (`src/notifications.rs`), which is true.
Existing accounts keep what their devices already said: on if any device opted in, otherwise unset.
`PUT /push` carries `include_content` (with `include_content_chosen` for a deliberate toggle) and saves it to the account; absent, it inherits.
`GET` and `PUT /push/preview` read and write the choice, and every device row is kept in step with it.
The client sends `include_content` only while an explicit toggle has not reached the server, so a device that never toggled cannot reset a choice made elsewhere.

## Why on by default

The preview is sealed to the device's own key, so the relay and APNs cannot read it, and the iOS lock-screen privacy setting still decides whether it shows.
The owner reads generic notifications as a bug, and a chat app that shows who wrote is what members expect.

## Turning it off

Settings, Notifications, "Show message text on your lock screen".
It is one choice for the whole account, so it applies to every device.

## Flipping the default

Change `DEFAULT_PUSH_PREVIEW` and nothing else.
Accounts that never chose follow it immediately, because sealing resolves the account value at send time.

## Old clients

A client older than this change sends `include_content: false` on every registration when the member never toggled, which is indistinguishable from a deliberate off.
The new client therefore sends `include_content_chosen: true` together with `include_content`, only for an explicit toggle.
The server saves `true` always, saves `false` only with the marker, and ignores an unmarked `false`.
An unmarked `false` while the account is unset leaves it unset, so the default applies, and it never overrides an explicit account value.

## Known gap

An old client's deliberate off, on an account that currently holds on, is not honoured until that client updates.
It looks exactly like a never-toggled old client, and the rule that protects the account from those has to win.
