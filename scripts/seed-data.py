#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fills a deployment with varied, realistic-looking chat activity.

Creates a channel named for today's date, then N accounts (default 10)
acting in parallel: short and long messages, emoji, markdown, code blocks,
mentions, polls, attachments, replies, threads, reactions, edits, deletes,
and pins, picked at random from a weighted set so the result reads like an
uneven real conversation rather than a uniform sample. Drives plain REST,
reusing scripts/lib/e2e_api.py rather than a second HTTP client.

Two things it does not do. It cannot fabricate a message's timestamp - the
server stamps every write with its own clock - so a single run cannot force
a day-divider across a real midnight; run it again on a later day against
the same deployment for that. And cleanup is not its job: it prints every
account, the channel, and the shared password it created, so a person can
find and remove them by hand.

    python3 scripts/seed-data.py --base-url http://localhost:8080 --confirm

An already-claimed deployment (one that already has an admin account) needs
that admin's credentials, to create the channel and mint an invite if the
join policy requires one:

    python3 scripts/seed-data.py --base-url http://localhost:8080 --confirm \\
        --admin-username alice --admin-password ... --invite-code XYZ

Nothing here has a default target, and nothing writes without --confirm; see
scripts/lib/seed_guard.py for why, and for the extra flag the one documented
live deployment needs on top of that.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

import seed_run  # noqa: E402


def _parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base-url", default=None,
                         help="the server to seed; no default, also readable "
                              "from SLIM_SEED_BASE_URL")
    parser.add_argument("--confirm", action="store_true",
                         help="required before anything is written")
    parser.add_argument("--i-know-this-is-production", action="store_true",
                         help="also required if the target is the documented "
                              "live deployment")
    parser.add_argument("--accounts", type=int, default=10,
                         help="how many accounts act in parallel (default 10)")
    parser.add_argument("--actions-per-account", type=int, default=40,
                         help="turns each account takes (default 40)")
    parser.add_argument("--concurrency", type=int, default=None,
                         help="how many accounts act at once; defaults to "
                              "the account count, lower it to throttle a run")
    parser.add_argument("--invite-code", default=None,
                         help="an existing invite code, if the join policy "
                              "requires one and no admin login is given")
    parser.add_argument("--admin-username", default=None,
                         help="an account with CREATE_INVITE and "
                              "MANAGE_CHANNELS, for an already-claimed "
                              "deployment")
    parser.add_argument("--admin-password", default=None)
    parser.add_argument("--password", default=None,
                         help="shared password for the seed accounts; "
                              "random per run if omitted")
    parser.add_argument("--channel-name", default=None,
                         help="defaults to today's date")
    parser.add_argument("--seed", type=int, default=None,
                         help="random seed, for a reproducible run")
    parser.add_argument("--username-tag", default=None,
                         help="namespaces seed account usernames; random per "
                              "run if omitted, so re-seeding the same "
                              "deployment never collides on username")
    parser.add_argument("--ollama", action="store_true",
                         help="generate message content with a local Ollama "
                              "model instead of the canned templates; off "
                              "by default, and any failure here (unreachable, "
                              "missing model, a bad response) just falls "
                              "back to the canned content rather than "
                              "aborting the run")
    parser.add_argument("--ollama-model", default=None,
                         help="overrides the model asked of Ollama "
                              "(default qwen3:8b); has no effect without "
                              "--ollama")
    args = parser.parse_args(argv)
    if args.admin_username and not args.admin_password:
        parser.error("--admin-username needs --admin-password")
    return args


def main(argv=None):
    return seed_run.run(_parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
