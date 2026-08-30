-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- The DELETE half of account deletion, which 0019 missed.
--
-- 0019 indexed the three UPDATE ... WHERE author_id = ? statements that
-- anonymize authored content. The DELETEs beside them in the same
-- transaction kept scanning: reactions, attachment_uploaders and
-- channel_overwrites are each reached by a column no index leads with, so
-- deleting one account read all three tables end to end while holding
-- SQLite's single write lock and every other write in the deployment waited.
-- reactions grows with all content and attachment_uploaders with all upload
-- volume, so those two scans only ever got longer.
--
-- member_roles is written in that same transaction, but its DELETE there
-- filters on user_id, which the (user_id, role_id) primary key already
-- serves, so it was never one of the scans. This index is for an unrelated
-- read: members_with_role (store/roles.rs) asks WHERE role_id = ?, which
-- that primary key cannot serve, and previously_visible_to
-- (http/overwrites.rs) calls it on every create, update and delete of a
-- role-scoped channel overwrite to work out who could already see it.
--
-- attachment_uploaders_uploaded_by also covers member_attachment_bytes
-- (store/analytics.rs), the operator's own storage-by-member view, which
-- was scanning the same table for the same column.
--
-- Full rather than partial, unlike 0019 and 0043: all four columns are
-- declared NOT NULL, so there are no rows for a partial index to exclude.
--
-- channel_overwrites leads with target_type because the query names it
-- literally, and the same index then also serves the sibling role deletion
-- (WHERE target_type = 'role' AND target_id = ?) in store/roles.rs, which
-- was equally uncovered.

CREATE INDEX reactions_user ON reactions(user_id);
CREATE INDEX attachment_uploaders_uploaded_by ON attachment_uploaders(uploaded_by);
CREATE INDEX member_roles_role ON member_roles(role_id);
CREATE INDEX channel_overwrites_target ON channel_overwrites(target_type, target_id);
