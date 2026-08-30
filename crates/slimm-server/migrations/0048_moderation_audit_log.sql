-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- A moderation trail for removals and timeouts, independent of and outliving
-- the two tables that hold what is currently in force.
--
-- space_removals and member_timeouts are both one row per member, replaced on
-- re-issue and deleted on restore or lift. That shape answers "is this person
-- removed right now" and nothing else: a restore erases the removal it
-- reverses, a re-issued timeout erases the one it replaces, and a moderator
-- asking "what has already been tried with this member" has nothing to read.
--
-- Adding lifted_at/lifted_by columns to those tables would not fix it. The row
-- is deleted, not marked, so keeping it for the lift would mean keeping a
-- soft-deleted row that every existing "is this in force" query would then
-- have to learn to skip - is_removed, the login check, timed_out_until, the
-- batched timeout lookup and the removal list, each of which is currently
-- correct because presence of the row *is* the answer. It also still only
-- holds one act per member, so the second removal overwrites the first.
--
-- One row per act, append-only, instead. The in-force tables keep their exact
-- current meaning, and history lives where history can accumulate.
--
-- actor_id is nulled on account deletion, the same treatment canvas_audit_log
-- and message_ops already give theirs. subject_id is deliberately left alone,
-- exactly as space_removals.user_id and member_timeouts.user_id are.
--
-- Both REFERENCES clauses below are belt and braces rather than the mechanism.
-- Deleting an account here is a tombstone UPDATE and never a DELETE FROM users
-- (see account_deletion.rs), so neither ON DELETE action can ever fire, and the
-- anonymization above is an explicit statement precisely because of that. The
-- clauses are kept because they match every sibling table and would be correct
-- if a real row delete ever arrived; 0020 and 0021 say the same of theirs, and
-- their comments read as though the constraint does the work. It does not.
--
-- No HTTP route reads this table yet, the same shape canvas_audit_log started
-- in, and it carries no sweep of its own.
CREATE TABLE moderation_audit_log (
    id         INTEGER PRIMARY KEY,
    actor_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    subject_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action     TEXT NOT NULL,
    reason     TEXT,
    -- When a timeout was due to lift; null for the acts that have no deadline.
    until      INTEGER,
    created_at INTEGER NOT NULL,
    CONSTRAINT moderation_audit_action
        CHECK (action IN ('remove', 'restore', 'timeout', 'timeout_cleared')),
    -- A lift carries the deadline it cut short, or none if it found nothing.
    CONSTRAINT moderation_audit_until CHECK (
        CASE action
            WHEN 'timeout' THEN until IS NOT NULL
            WHEN 'timeout_cleared' THEN 1
            ELSE until IS NULL
        END
    )
) STRICT;

-- The read this exists for: one member's history, oldest to newest.
CREATE INDEX moderation_audit_log_subject ON moderation_audit_log(subject_id, created_at);

-- Account deletion filters by actor, the same shape canvas_audit_log_actor uses.
CREATE INDEX moderation_audit_log_actor ON moderation_audit_log(actor_id) WHERE actor_id IS NOT NULL;

-- Everything in force right now becomes the first entry of its own history,
-- so a deployment that upgrades does not start with a member whose standing
-- removal is invisible here. Nothing that was already restored or lifted can
-- be recovered: those rows are gone, which is the whole reason for this table.
INSERT INTO moderation_audit_log (actor_id, subject_id, action, reason, until, created_at)
SELECT actor_id, subject_id, action, reason, until, created_at
FROM (
    SELECT removed_by AS actor_id,
           user_id    AS subject_id,
           'remove'   AS action,
           reason     AS reason,
           NULL       AS until,
           removed_at AS created_at
    FROM space_removals
    UNION ALL
    SELECT issued_by  AS actor_id,
           user_id    AS subject_id,
           'timeout'  AS action,
           reason     AS reason,
           until      AS until,
           issued_at  AS created_at
    FROM member_timeouts
)
ORDER BY created_at;
