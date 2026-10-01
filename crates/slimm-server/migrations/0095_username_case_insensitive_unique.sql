-- Usernames become unique case-insensitively among live accounts, so "Alice"
-- can no longer register beside "alice".
--
-- A deployment that already holds such a pair must not fail to start, and no
-- account is deleted or merged. The earliest account of each colliding group
-- (see below) keeps its name; every other one is renamed to its
-- own name, cut to 23 characters, plus "_" and the last 8 hex digits of its
-- id, which keeps it a valid username of at most 32 characters. Display names
-- are untouched. Each rename is recorded in username_collision_renames so an
-- operator can tell the member their new sign-in name.
--
-- usernames are validated ASCII, which is what makes SQLite's lower() exact.
CREATE TABLE username_collision_renames (
    user_id      BLOB PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    old_username TEXT NOT NULL,
    new_username TEXT NOT NULL,
    renamed_at   INTEGER NOT NULL
) STRICT;

-- The name stays with the account that was active most recently, so a live
-- member is never renamed in favour of a dormant one: an account with a
-- non-revoked session ranks first, then by its latest session activity, else
-- its latest device last_seen_at, else its latest message. Ties go to the
-- earliest created_at, then id.
CREATE TEMP TABLE username_collision_losers AS
SELECT id FROM (
    SELECT id, row_number() OVER (
        PARTITION BY lower(username)
        ORDER BY has_live DESC, activity DESC, created_at, id
    ) AS rank
    FROM (
        SELECT u.id, u.username, u.created_at,
               EXISTS (SELECT 1 FROM sessions s
                       WHERE s.user_id = u.id AND s.revoked_at IS NULL) AS has_live,
               COALESCE(
                   (SELECT max(COALESCE(s.last_used_at, s.created_at)) FROM sessions s
                    WHERE s.user_id = u.id AND s.revoked_at IS NULL),
                   (SELECT max(d.last_seen_at) FROM devices d WHERE d.user_id = u.id),
                   (SELECT max(m.created_at) FROM messages m WHERE m.author_id = u.id),
                   0
               ) AS activity
        FROM users u
        WHERE u.deleted_at IS NULL
    )
) WHERE rank > 1;

INSERT INTO username_collision_renames (user_id, old_username, new_username, renamed_at)
SELECT u.id, u.username,
       substr(u.username, 1, 23) || '_' || lower(substr(hex(u.id), -8)),
       CAST(strftime('%s', 'now') AS INTEGER) * 1000
FROM users u
JOIN username_collision_losers l ON l.id = u.id;

UPDATE users
SET username = (SELECT new_username FROM username_collision_renames WHERE user_id = users.id)
WHERE id IN (SELECT id FROM username_collision_losers);

DROP TABLE username_collision_losers;

CREATE UNIQUE INDEX users_username_lower_live ON users(lower(username)) WHERE deleted_at IS NULL;
