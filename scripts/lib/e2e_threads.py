# SPDX-License-Identifier: Apache-2.0
"""Opening a thread, replying inside it, and the property most likely to
regress quietly: a thread channel must never show up beside the real ones.

'Reply in thread' lives behind the same context menu 'Reply' does (see
e2e_replies.py and e2e_admin.py's own module doc), so opening the thread is
done at the API here, the same substitution. A thread also has no rail row
by design (docs/decisions/0005-threads.md), so there is no click that lands
on it either, the same reason the channel rail itself is reached by URL
elsewhere in this harness (see docs/e2e.md's "Driving a canvas app"); once
open, sending in it and reading it back is the ordinary composer and
transcript, checked through the real UI on both clients.

A bystander only learns a thread's reply count on their next fetch of the
parent channel, never live (CLAUDE.md's own note on the feature says so), so
the reply-count check below forces a real reconnect rather than trusting an
already-open tab to notice on its own.

`L.THREAD_HEADER` is the back button's tooltip rather than the bar's own
title, which is not an oversight. An `AppBar`'s title produces no semantics
node of its own in Flutter web: it merges into the bar's node, which this
harness's collector cannot see, since that collector keeps only leaves on
purpose (widening it would let two nodes answer one `find()` across every
other scenario). Wrapping the title in `Semantics(container: true)` was
tried and does separate it in `flutter_test`'s framework-level tree, but
does not change what the web engine projects into the DOM, which is the only
thing a browser run can read. The tooltip is a real leaf, appears exactly
once in the whole client, and only on this screen, so it proves the thread
screen rendered just as well.
"""
import time

import e2e_labels as L


def open_reply_and_stay_off_the_rail(sender, receiver, channel, admin_api,
                                      member_api):
    stamp = str(int(time.time()))
    root_text = f"a thread root {stamp}"
    thread_text = f"a reply inside the thread {stamp}"
    api = admin_api

    for c in (sender, receiver):
        c.click(channel)
        c.wait_for(L.COMPOSER)
    sender.type_into(L.COMPOSER, root_text)
    sender.click(L.SEND, settle=2)
    receiver.wait_for(root_text)

    channel_id = api.channel_named(channel)['id']
    root = api.message_with(channel_id, root_text)
    thread = api.open_thread(channel_id, root['id'])
    thread_id = thread['id']
    assert thread['parent_message_id'] == root['id'], \
        f"the thread does not name its root message: {thread}"
    print(f'  a thread was opened on the root message: {thread_id}')

    for who, caller in (('the admin', admin_api), ('the member', member_api)):
        listed = {ch['id'] for ch in caller.channels()}
        assert thread_id not in listed, \
            f"the thread channel showed up in {who}'s channel list"
    print("  and it does not appear in either account's ordinary channel list")

    for c in (sender, receiver):
        c.ev(f"location.hash = '#/thread/{thread_id}'")
        time.sleep(2)
        c.wait_for(L.THREAD_HEADER)
    print('  both clients reached the thread; there is no rail row to it')

    sender.wait_for(L.COMPOSER)
    sender.type_into(L.COMPOSER, thread_text)
    sender.click(L.SEND, settle=2)
    receiver.wait_for(thread_text, timeout=30)
    print('  a reply sent inside the thread reached the other client live')

    stored = api.messages(thread_id)
    assert any(thread_text in (m.get('content') or '') for m in stored), \
        'the server does not hold the reply inside the thread channel'

    # A thread route has no rail, so a hash change is what gets the receiver back to a screen the next scenario can find a channel row on.
    receiver.ev("location.hash = '#/channels'")
    time.sleep(2)

    # A fresh reload is a real returning visit, and lands on the shell rather than the thread route it left from, where there is no rail row to click at all.
    origin = sender.ev("location.origin")
    sender.go_away()
    sender.come_back(f"{origin}/#/channels")
    sender.click(channel)
    sender.wait_for(L.COMPOSER)
    summary = sender.wait_for('open thread.', timeout=30)
    assert '1 repl' in summary['t'].lower(), \
        f'the reply-count affordance does not read 1 reply: {summary["t"]!r}'
    sender.shot('thread-reply-count')
    print(f'  the parent message now shows the reply-count affordance: '
          f'{summary["t"]!r}')
