-- Rotation confirms before it retires.
--
-- A rotation commits server-side before its response reaches the client, so a
-- lost response left the client holding a token the server had already spent.
-- Its next attempt was a replay, which signed the user out. The token a
-- rotation spends now stays usable until the client proves it received the
-- replacement, and only then is it retired.

ALTER TABLE refresh_tokens ADD COLUMN retired_at INTEGER;

-- The replacement this token issued, so re-rotating a pending token can revoke
-- the successor the client never received rather than leaving it live.
ALTER TABLE refresh_tokens ADD COLUMN successor_hash TEXT;

-- The predecessor this access token confirms, retired on its first use.
ALTER TABLE access_tokens ADD COLUMN confirms_refresh_hash TEXT;

-- Tokens spent under the old rules were retired the moment they were used.
-- Without this they would all become pending, and every one of them replayable.
UPDATE refresh_tokens SET retired_at = used_at WHERE used_at IS NOT NULL;
