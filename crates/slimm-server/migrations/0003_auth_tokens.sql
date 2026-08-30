-- SPDX-License-Identifier: AGPL-3.0-only
-- Phase 1 auth credential rows.
--
-- 0002 already defines the durable anchors: users (with an Argon2id
-- password_hash), devices, sessions, refresh_tokens (hash + rotating family_id),
-- and password_reset_codes. This migration adds the two short-lived credential
-- rows that hang off a session:
--
--   access_tokens   opaque bearer tokens presented on every authenticated
--                   request. Stored only as a SHA-256 hash. Short-lived, so the
--                   hot auth path is one indexed lookup with an expiry check and
--                   no join; user_id and device_id are denormalized on for that.
--   ws_tickets      single-use, very short-lived tickets minted from a live
--                   session over REST, then redeemed once to open a WebSocket.
--
-- Revocation is instant: revoking a session deletes its access_tokens and
-- ws_tickets and marks its refresh_tokens revoked, so a killed session's bearer
-- token stops resolving on the very next request. Refresh tokens are never
-- deleted on rotation, only marked used, so replay of a spent token is still
-- detectable and revokes the whole family.

CREATE TABLE access_tokens (
    token_hash TEXT PRIMARY KEY,          -- SHA-256 hex of the opaque bearer secret
    session_id BLOB NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    user_id    BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id  BLOB NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    issued_at  INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
) STRICT;
CREATE INDEX access_tokens_session ON access_tokens(session_id);

CREATE TABLE ws_tickets (
    ticket_hash TEXT PRIMARY KEY,         -- SHA-256 hex of the opaque ticket secret
    session_id  BLOB NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    user_id     BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id   BLOB NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    issued_at   INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL,
    used_at     INTEGER                   -- single-use: set on redemption
) STRICT;
CREATE INDEX ws_tickets_session ON ws_tickets(session_id);
