-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Space usage analytics: an opt-in toggle plus a small memory-sample table.
--
-- Defaults to off. Nothing here is derived from anything new: message counts
-- and active hours are computed on read straight from the existing `messages`
-- table, so this migration adds no column to it at all. The toggle instead
-- gates whether the whole analytics screen answers anything, derived or
-- recorded, the same "off means the feature does not run" shape as an unset
-- push relay: an opt-in analytics store that switched itself on unasked would
-- contradict this project's own no-automated-scanning posture.
--
-- `space_metrics_samples` holds the one recorded series (resident memory),
-- sampled lazily on a read of the analytics screen rather than by a
-- background timer, so a deployment with the toggle on that nobody ever
-- looks at costs nothing beyond this table's own near-empty size. See
-- `store/analytics.rs` for the sampling and retention logic.
ALTER TABLE space_settings ADD COLUMN analytics_enabled INTEGER NOT NULL DEFAULT 0
    CHECK (analytics_enabled IN (0, 1));

CREATE TABLE space_metrics_samples (
    id         INTEGER PRIMARY KEY,
    sampled_at INTEGER NOT NULL,
    rss_bytes  INTEGER NOT NULL
) STRICT;
CREATE INDEX space_metrics_samples_time ON space_metrics_samples(sampled_at);
