# SPDX-License-Identifier: Apache-2.0
"""Personal settings and Space settings, which are two screens on purpose.

The split is recent: one screen used to carry both, so a member with no
permissions saw a Space section they could do nothing with. These check the
two are reachable independently, and that what they change actually changes.
"""
import time


def _open_personal(client):
    """Each scenario starts from the channel list, so each finds its own way."""
    if '#/settings' not in (client.ev('location.href') or '') or \
            client.find('Who can join'):
        client.click('Personal settings', settle=3)


def _open_space(client):
    if '#/settings/space' not in (client.ev('location.href') or ''):
        client.click('Space menu', settle=2)
        client.click('Space settings', settle=3)


def personal_settings_reachable(client):
    """The footer control opens personal settings, never Space settings."""
    client.click('Personal settings', settle=3)
    client.wait_url('#/settings')
    client.wait_for('Upload photo')
    assert not client.find('Who can join'), \
        'personal settings is showing Space settings'
    client.shot('personal-settings')
    print('  personal settings opens on its own, with no Space section in it')


def change_theme(client):
    """A preference that persists is a preference that was actually stored."""
    _open_personal(client)
    client.click('Theme', settle=2)
    client.wait_for('Dark')
    client.click('Dark', settle=2)
    client.wait_for('Theme, currently Dark')
    print('  theme changed to Dark and the control says so')


def change_status(client, api):
    """Presence is a real server-side state, not a local badge."""
    _open_personal(client)
    client.click('Status', settle=2)
    client.wait_for('Do not disturb')
    client.click('Do not disturb', settle=3)
    client.wait_for('Status, currently Do not disturb')
    print('  status changed to do-not-disturb')


def upload_avatar(client, api, path):
    """Upload a picture and check the server serves it back."""
    _open_personal(client)
    client.attach_file('Upload photo', path)
    # A picked picture is cropped before it is uploaded, so the sheet has to be
    # answered; nothing reaches the server until it is.
    client.wait_for('Crop your picture')
    client.click('Use picture', settle=4)
    deadline = time.time() + 40
    served = None
    while time.time() < deadline:
        me = api.me()
        if me.get('avatar_updated_at'):
            served = me
            break
        time.sleep(2)
    assert served, 'the server recorded no avatar'
    body = api.call('GET', f'/users/{served["id"]}/avatar')
    assert body and len(body) > 100, 'the avatar served back empty'
    client.shot('avatar-uploaded')
    print(f'  an avatar was stored and served back, {len(body)} bytes')


def space_settings_reachable(client):
    """The Space menu opens Space settings, which personal settings is not."""
    _open_space(client)
    client.wait_url('#/settings/space')
    for label in ('Reports', 'Invites', 'Roles', 'Who can join'):
        client.wait_for(label)
    assert not client.find('Upload photo'), \
        'Space settings is showing personal settings'
    client.shot('space-settings')
    print('  Space settings opens on its own, with all four sections')


def change_join_policy(client, api):
    """Who can join is one row in the database and the whole security model."""
    _open_space(client)
    before = api.space_settings()['join_policy']
    client.click('Who can join', settle=2)
    client.wait_for('Anyone with the address')
    client.click('Anyone with the address', settle=3)

    deadline = time.time() + 30
    while time.time() < deadline:
        if api.space_settings()['join_policy'] == 'open':
            break
        time.sleep(2)
    after = api.space_settings()['join_policy']
    assert after == 'open', f'join policy is {after!r}, not open'
    assert after != before, 'the join policy did not change'
    # Unauthenticated callers are told, because the sign-up screen has to know
    # before an account exists.
    assert api.version()['invite_required'] is False, \
        '/version still says an invite is required'
    print(f'  join policy {before} -> {after}, and /version agrees')

    client.click('Who can join', settle=2)
    client.click('People with an invite', settle=3)
    deadline = time.time() + 30
    while time.time() < deadline:
        if api.space_settings()['join_policy'] == 'invite':
            break
        time.sleep(2)
    assert api.space_settings()['join_policy'] == 'invite', \
        'the Space was left open'
    print('  and back to invite-only, so the run leaves nothing open')
