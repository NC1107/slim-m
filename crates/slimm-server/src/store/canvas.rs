// SPDX-License-Identifier: AGPL-3.0-only
//! Canvas object persistence and the viewport read path over the R-Tree that
//! migration 0015 keeps in sync by trigger.
//!
//! Two things about this read path are worth knowing before changing it.
//!
//! R-Tree coordinates are 32-bit floats, and SQLite rounds a bounding box
//! outwards when it stores one, so the index over-reports near its precision
//! limit and never under-reports. Every query therefore repeats the
//! intersection test in exact `REAL` arithmetic against `canvas_objects`, and
//! the R-Tree is only ever a way to avoid looking at most rows.
//!
//! The delta is geometric, not a diff against server-held state. A client
//! sends the rectangle it is entering and the one it is leaving, and gets
//! back what is in the first and not the second, plus anything inside both
//! that is newer than its cursor. Nothing per-connection is stored, so a
//! reconnect costs one ordinary request and a pan is idempotent.
//!
//! `CROSS JOIN` in the viewport read is load-bearing, not style. It pins the
//! R-Tree as the outer loop. Left as a plain join, SQLite on a database that
//! has never been ANALYZEd drives from `canvas_objects` instead and probes the
//! R-Tree by rowid, which reads every object in the channel and prunes
//! nothing; `tests/canvas.rs` asserts the plan rather than trusting it.

use anyhow::Context;

use super::{Store, now_ms};
use crate::ids::{CanvasObjectId, ChannelId, Seq, UserId};

/// Half-width of the bounded world. The canvas is large but finite (owner
/// decision), and an object outside it could never be reached by panning.
pub const WORLD_LIMIT: f64 = 5_000_000.0;

/// A placed canvas object.
#[derive(Debug, Clone)]
pub struct CanvasObject {
    pub id: CanvasObjectId,
    pub kind: String,
    pub z_index: i64,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    /// Kind-specific fields as a JSON object, opaque to the server.
    pub props: String,
    pub author_id: Option<UserId>,
    pub seq: Seq,
    pub created_at: i64,
}

/// An axis-aligned rectangle in world coordinates.
#[derive(Debug, Clone, Copy)]
pub struct Rect {
    pub min_x: f64,
    pub min_y: f64,
    pub max_x: f64,
    pub max_y: f64,
}

/// One viewport read. `previous` is the rectangle the client is leaving, and
/// its absence means a cold fetch of `view` with nothing held back.
#[derive(Debug, Clone)]
pub struct ViewportQuery {
    pub view: Rect,
    pub previous: Option<Rect>,
    pub after_seq: i64,
    pub limit: i64,
}

/// Why placing an object failed.
#[derive(Debug)]
pub enum PlaceError {
    /// This id already belongs to an object in another channel.
    IdConflict,
    /// The object's bounds are not finite, have negative extent, or fall
    /// outside the bounded world.
    OutOfBounds,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for PlaceError {
    fn from(err: sqlx::Error) -> Self {
        PlaceError::Internal(err.into())
    }
}

impl From<anyhow::Error> for PlaceError {
    fn from(err: anyhow::Error) -> Self {
        PlaceError::Internal(err)
    }
}

/// A 24-bit discriminant of a channel id, stored on every object and used as
/// the R-Tree's third dimension. Drawn from the UUIDv7's random tail, not its
/// timestamp prefix, which channels created in the same millisecond share.
pub(crate) fn channel_key(channel_id: ChannelId) -> i64 {
    let bytes = channel_id.0.as_bytes();
    i64::from(bytes[13]) << 16 | i64::from(bytes[14]) << 8 | i64::from(bytes[15])
}

fn valid_bounds(x: f64, y: f64, w: f64, h: f64) -> bool {
    [x, y, w, h].iter().all(|v| v.is_finite())
        && w >= 0.0
        && h >= 0.0
        && x >= -WORLD_LIMIT
        && y >= -WORLD_LIMIT
        && x + w <= WORLD_LIMIT
        && y + h <= WORLD_LIMIT
}

impl Store {
    /// Places an object on a channel's canvas, idempotent by `id` and taking
    /// the next value from that channel's `canvas` sequence stream, which is
    /// independent of its message stream.
    pub async fn place_canvas_object(
        &self,
        channel_id: ChannelId,
        author_id: UserId,
        id: CanvasObjectId,
        kind: &str,
        bounds: (f64, f64, f64, f64),
        props: &str,
    ) -> Result<CanvasObject, PlaceError> {
        let (x, y, w, h) = bounds;
        if !valid_bounds(x, y, w, h) {
            return Err(PlaceError::OutOfBounds);
        }

        // Reads the id before deciding to write, so the write lock is taken up
        // front (see `Store::begin_write`).
        let mut tx = self.begin_write().await?;
        if let Some(existing) = fetch_object(&mut tx, id).await? {
            tx.commit().await?;
            return match existing.0 == channel_id {
                true => Ok(existing.1),
                false => Err(PlaceError::IdConflict),
            };
        }

        let seq = sqlx::query_scalar!(
            r#"UPDATE channel_seq_counters SET next_seq = next_seq + 1
               WHERE channel_id = ? AND stream = 'canvas'
               RETURNING next_seq - 1 AS "seq!: i64""#,
            channel_id
        )
        .fetch_optional(&mut *tx)
        .await?
        .context("channel has no canvas sequence counter")?;

        let key = channel_key(channel_id);
        let now = now_ms();
        // `z_index` is seeded from `seq`, so the default paint order is the
        // order things were drawn in and raising an object is a later edit.
        sqlx::query!(
            r#"INSERT INTO canvas_objects
                   (id, channel_id, channel_key, kind, z_index, x, y, w, h, props,
                    author_id, seq, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"#,
            id,
            channel_id,
            key,
            kind,
            seq,
            x,
            y,
            w,
            h,
            props,
            author_id,
            seq,
            now
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;

        Ok(CanvasObject {
            id,
            kind: kind.to_owned(),
            z_index: seq,
            x,
            y,
            w,
            h,
            props: props.to_owned(),
            author_id: Some(author_id),
            seq: Seq(seq),
            created_at: now,
        })
    }

    /// Moves or resizes an object. Named `UPDATE OF` columns are what fire the
    /// R-Tree trigger, so this is the only write that has to touch all four.
    pub async fn move_canvas_object(
        &self,
        id: CanvasObjectId,
        bounds: (f64, f64, f64, f64),
    ) -> Result<bool, PlaceError> {
        let (x, y, w, h) = bounds;
        if !valid_bounds(x, y, w, h) {
            return Err(PlaceError::OutOfBounds);
        }
        let affected = sqlx::query!(
            "UPDATE canvas_objects SET x = ?, y = ?, w = ?, h = ?
             WHERE id = ? AND deleted_at IS NULL",
            x,
            y,
            w,
            h,
            id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(affected > 0)
    }

    /// Soft-deletes an object, which the trigger takes out of the R-Tree.
    pub async fn remove_canvas_object(&self, id: CanvasObjectId) -> anyhow::Result<bool> {
        let now = now_ms();
        let affected = sqlx::query!(
            "UPDATE canvas_objects SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL",
            now,
            id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(affected > 0)
    }

    /// The channel's live objects intersecting `view`, z-ordered, held back to
    /// what the caller does not already have when `previous` is given.
    pub async fn viewport_objects(
        &self,
        channel_id: ChannelId,
        query: &ViewportQuery,
    ) -> anyhow::Result<Vec<CanvasObject>> {
        let key = channel_key(channel_id);
        let view = query.view;
        let previous = query.previous.unwrap_or(Rect {
            min_x: 0.0,
            min_y: 0.0,
            max_x: 0.0,
            max_y: 0.0,
        });
        let has_previous = i64::from(query.previous.is_some());

        let rows = sqlx::query_as!(
            CanvasObject,
            r#"SELECT o.id AS "id!: CanvasObjectId", o.kind AS "kind!",
                      o.z_index AS "z_index!: i64",
                      o.x AS "x!: f64", o.y AS "y!: f64",
                      o.w AS "w!: f64", o.h AS "h!: f64",
                      o.props AS "props!", o.author_id AS "author_id: UserId",
                      o.seq AS "seq!: Seq", o.created_at AS "created_at!: i64"
               FROM canvas_rtree r
               CROSS JOIN canvas_objects o ON o.rt_id = r.rt_id
               WHERE r.min_key <= ? AND r.max_key >= ?
                 AND r.max_x >= ? AND r.min_x <= ?
                 AND r.max_y >= ? AND r.min_y <= ?
                 AND o.channel_id = ? AND o.deleted_at IS NULL
                 AND o.x <= ? AND o.x + o.w >= ?
                 AND o.y <= ? AND o.y + o.h >= ?
                 AND (? = 0 OR o.seq > ?
                      OR NOT (o.x <= ? AND o.x + o.w >= ?
                              AND o.y <= ? AND o.y + o.h >= ?))
               ORDER BY o.z_index, o.seq
               LIMIT ?"#,
            key,
            key,
            view.min_x,
            view.max_x,
            view.min_y,
            view.max_y,
            channel_id,
            view.max_x,
            view.min_x,
            view.max_y,
            view.min_y,
            has_previous,
            query.after_seq,
            previous.max_x,
            previous.min_x,
            previous.max_y,
            previous.min_y,
            query.limit
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// The channel's highest assigned canvas sequence, which a client keeps as
    /// the cursor for its next viewport read.
    pub async fn latest_canvas_seq(&self, channel_id: ChannelId) -> anyhow::Result<i64> {
        let seq = sqlx::query_scalar!(
            r#"SELECT next_seq - 1 AS "seq!: i64" FROM channel_seq_counters
               WHERE channel_id = ? AND stream = 'canvas'"#,
            channel_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(seq.unwrap_or(0))
    }
}

/// Fetches one live object and the channel it belongs to, for the idempotency
/// check on placement.
async fn fetch_object(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    id: CanvasObjectId,
) -> anyhow::Result<Option<(ChannelId, CanvasObject)>> {
    let row = sqlx::query!(
        r#"SELECT channel_id AS "channel_id!: ChannelId", id AS "id!: CanvasObjectId",
                  kind AS "kind!", z_index AS "z_index!: i64",
                  x AS "x!: f64", y AS "y!: f64", w AS "w!: f64", h AS "h!: f64",
                  props AS "props!", author_id AS "author_id: UserId",
                  seq AS "seq!: Seq", created_at AS "created_at!: i64"
           FROM canvas_objects WHERE id = ? AND deleted_at IS NULL"#,
        id
    )
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row.map(|r| {
        (
            r.channel_id,
            CanvasObject {
                id: r.id,
                kind: r.kind,
                z_index: r.z_index,
                x: r.x,
                y: r.y,
                w: r.w,
                h: r.h,
                props: r.props,
                author_id: r.author_id,
                seq: r.seq,
                created_at: r.created_at,
            },
        )
    }))
}
