-- Usernames become unique case-insensitively among live accounts, so "Alice"
-- can no longer register beside "alice".
--
-- A deployment that already holds such a pair must not fail to start, and no
-- account is deleted or merged. The earliest account of each colliding group
-- (by created_at, then id) keeps its name; every later one is renamed to its
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

CREATE TEMP TABLE username_collision_losers AS
SELECT id FROM (
    SELECT id, row_number() OVER (
        PARTITION BY lower(username) ORDER BY created_at, id
    ) AS rank
    FROM users
    WHERE deleted_at IS NULL
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
