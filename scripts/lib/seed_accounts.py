# SPDX-License-Identifier: Apache-2.0
"""Registers the seed accounts and the day's channel.

Reuses `e2e_api.Api` for every call rather than a second HTTP client, and
follows `e2e_seed.py`'s own pattern of a first-account-claims-a-fresh-
deployment flow - extended here to also work against an already-claimed one,
via an admin login that mints an invite and creates the channel itself.
"""
import urllib.error

import e2e_api
import seed_backoff
import seed_content


class AccountSetupError(Exception):
    """A refusal to continue, with the reason a person should see."""


def obtain_invite_code(base_url, accounts_needed, invite_code, admin_username,
                        admin_password, device_prefix):
    """Returns (code_or_None, admin_api_or_None).

    An explicit code or an admin login (which mints one sized for the whole
    run) is used directly. Otherwise this returns no code at all and leaves
    it to `register_accounts`: whether one turns out to be needed depends on
    whether the deployment is already claimed, which nothing can answer
    ahead of actually trying to register the first account.
    """
    if invite_code:
        return invite_code, None

    if admin_username:
        admin_api = e2e_api.Api(base_url)
        try:
            admin_api.login(admin_username, admin_password,
                             device=f"{device_prefix}-admin")
            minted = admin_api.call("POST", "/invites",
                                     {"max_uses": accounts_needed})
        except urllib.error.HTTPError as exc:
            raise AccountSetupError(
                "could not log in as the given admin account, or mint an "
                f"invite from it: {seed_backoff.describe_error(exc)}") from exc
        return minted["code"], admin_api

    return None, None


def _mint_invite_if_possible(api, uses_needed):
    """Tries to mint a code from the account that just registered.

    The first account may have just claimed a previously unclaimed
    deployment and gained CREATE_INVITE along with it; if not (an open join
    policy, or someone else already claimed it), the remaining accounts can
    still register with no code at all, so a failure here is swallowed
    rather than fatal.
    """
    try:
        minted = seed_backoff.call_with_backoff(
            lambda: api.call("POST", "/invites", {"max_uses": uses_needed}))
        return minted["code"]
    except urllib.error.HTTPError:
        return None


def register_accounts(base_url, count, password, invite_code, device_prefix,
                       username_tag=""):
    """Registers `count` fresh accounts, retrying past the tight, IP-keyed
    password bucket rather than firing every registration at once.

    With no code given up front, the first account registers with none at
    all: on a still-unclaimed deployment that both succeeds and claims it,
    at which point it mints a code of its own for the rest (see
    `_mint_invite_if_possible`), the same shape `e2e_seed.py` already uses
    for its two accounts, generalised to N. `username_tag` namespaces the
    accounts so a second run against the same deployment does not collide
    with the first's usernames.
    """
    accounts = []
    working_code = invite_code
    for index in range(count):
        username, display = seed_content.persona(index, tag=username_tag)
        api = e2e_api.Api(base_url)
        body = {"username": username, "display_name": display,
                 "password": password, "device_name": f"{device_prefix}-{index}"}
        if working_code:
            body["invite_code"] = working_code
        try:
            got = seed_backoff.call_with_backoff(
                lambda b=body: api.call("POST", "/auth/register", b))
        except urllib.error.HTTPError as exc:
            hint = ("" if working_code else
                    "; pass --invite-code, or --admin-username and "
                    "--admin-password so this can mint one")
            raise AccountSetupError(
                f"could not register seed account {username!r}: "
                f"{seed_backoff.describe_error(exc)}{hint}") from exc
        api.token = got["access_token"]
        accounts.append({"username": username, "display_name": display,
                          "api": api})
        if index == 0 and working_code is None and count > 1:
            working_code = _mint_invite_if_possible(api, count - 1)
    return accounts


def create_seed_channel(accounts, admin_api, channel_name):
    """Creates the day's channel with whichever caller holds MANAGE_CHANNELS.

    Prefers an already-authenticated admin; otherwise falls back to the
    first seed account, which only holds that permission when it just
    claimed a fresh, previously unclaimed deployment.
    """
    creator = admin_api or (accounts[0]["api"] if accounts else None)
    if creator is None:
        raise AccountSetupError("no account available to create the channel")
    try:
        return seed_backoff.call_with_backoff(
            lambda: creator.call(
                "POST", "/channels", {"name": channel_name, "kind": "text"}))
    except urllib.error.HTTPError as exc:
        if exc.code == 403:
            raise AccountSetupError(
                "the channel could not be created (403): the seed account "
                "has no MANAGE_CHANNELS permission. Point this at a fresh, "
                "unclaimed deployment so the first account auto-claims it, "
                "or pass --admin-username and --admin-password for an "
                "already-claimed one") from exc
        raise AccountSetupError(
            f"could not create the channel: "
            f"{seed_backoff.describe_error(exc)}") from exc
