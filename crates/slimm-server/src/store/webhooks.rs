// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Incoming webhooks: a user-shaped principal with no session and no roles.
//!
//! See `docs/decisions/0030-incoming-webhooks.md`. Two things depart from
//! `docs/decisions/0028-bot-accounts.md`'s bot shape, and they are the whole
//! of what makes this module different from `bots.rs`:
//!
//! **No session.** [`Store::authenticate_webhook`] returns a
//! [`WebhookContext`], never a [`super::sessions::SessionContext`] - a
//! session is what makes a credential able to *read*, and a webhook must
//! never read. Nothing in this module can produce one, so no `Authed`
//! extractor can ever accept a webhook token; `tests/webhooks.rs` asserts
//! that structurally.
//!
//! **No roles.** [`super::permissions`]'s role loader returns an empty
//! context for any `is_webhook` principal before it even asks which roles
//! that id holds, so a webhook cannot inherit `@everyone`'s grant either, not
//! even by accident. That one guard is what makes "no MENTION_EVERYONE, no
//! ADMINISTRATOR, never counted as an administrator" true everywhere
//! permissions are evaluated, rather than a rule every caller has to
//! remember on its own.

use crate::auth::{generate_secret, hash_secret};
use crate::ids::{ChannelId, MessageId, UserId, WebhookId};

use super::{Store, now_ms};

/// A webhook, as an operator will see it once the admin surface exists.
/// Carries no secret.
#[derive(Debug, Clone)]
pub struct Webhook {
    pub id: WebhookId,
    /// The `users.id` this webhook posts as - a message's `author_id`, once
    /// it has posted one. Exposed for the same reason `Bot::user_id` is: a
    /// caller correlates a webhook with what it wrote through this, not
    /// through [`WebhookId`], which never appears on a message at all.
    pub principal_id: UserId,
    pub channel_id: ChannelId,
    pub label: String,
    pub created_at: i64,
    pub last_delivery_at: Option<i64>,
}

/// A newly minted webhook and the one time its token is ever legible.
pub struct NewWebhook {
    pub webhook: Webhook,
    pub token: String,
}

/// What a presented `(webhook_id, token)` pair resolves to: enough to post as
/// this webhook's principal in its one fixed channel, and nothing else. Not a
/// [`super::sessions::SessionContext`] and cannot become one - see this
/// module's own doc.
pub struct WebhookContext {
    pub principal_id: UserId,
    pub channel_id: ChannelId,
}

impl Store {
    /// Mints a webhook and its first token in one transaction, the same
    /// "nothing useful without one" shape [`Store::create_bot`] uses.
    ///
    /// `label` becomes both the admin-facing name and the principal's
    /// `display_name`; the principal's `username` is generated rather than
    /// chosen, since nothing ever addresses a webhook by it - see this
    /// module's own doc for why the account still needs one at all.
    pub async fn create_webhook(
        &self,
        channel_id: ChannelId,
        label: &str,
    ) -> anyhow::Result<NewWebhook> {
        let webhook_id = WebhookId::generate();
        let user_id = UserId::generate();
        let token = generate_secret();
        let token_hash = hash_secret(&token);
        let now = now_ms();
        let username = format!("webhook-{user_id}");

        let mut tx = self.pool.begin().await?;
        sqlx::query!(
            "INSERT INTO users (id, username, display_name, created_at, is_webhook)
             VALUES (?, ?, ?, ?, 1)",
            user_id,
            username,
            label,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO webhooks (id, user_id, channel_id, token_hash, label, created_at)
             VALUES (?, ?, ?, ?, ?, ?)",
            webhook_id,
            user_id,
            channel_id,
            token_hash,
            label,
            now
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;

        Ok(NewWebhook {
            webhook: Webhook {
                id: webhook_id,
                principal_id: user_id,
                channel_id,
                label: label.to_owned(),
                created_at: now,
                last_delivery_at: None,
            },
            token,
        })
    }

    /// Resolves a presented `(webhook_id, token)` pair, or `None` if the id
    /// is unknown, the token is wrong, or the webhook has been revoked - the
    /// three cases the delivery route must answer identically (a uniform
    /// 404), which is why this collapses them into one `None` rather than
    /// telling the caller which.
    pub async fn authenticate_webhook(
        &self,
        webhook_id: WebhookId,
        token: &str,
    ) -> anyhow::Result<Option<WebhookContext>> {
        let hash = hash_secret(token);
        let row = sqlx::query!(
            r#"SELECT user_id AS "user_id!: UserId", channel_id AS "channel_id!: ChannelId"
               FROM webhooks WHERE id = ? AND token_hash = ?"#,
            webhook_id,
            hash
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| WebhookContext {
            principal_id: r.user_id,
            channel_id: r.channel_id,
        }))
    }

    /// Stamps `last_delivery_at` after a successful post. Not debounced the
    /// way a bot token's `last_used_at` is: a webhook fires orders of
    /// magnitude less often than a polling bot ever does, so a write per
    /// delivery costs nothing worth guarding against.
    pub async fn touch_webhook_delivery(&self, webhook_id: WebhookId) -> anyhow::Result<()> {
        let now = now_ms();
        sqlx::query!(
            "UPDATE webhooks SET last_delivery_at = ? WHERE id = ?",
            now,
            webhook_id
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Stores a webhook post's per-post `username` label against the message
    /// it landed on. Never written to `users.display_name` or returned as a
    /// message's `author_display_name` - see this module's own doc and the
    /// decision record's "`username` becomes a label" section. Called at
    /// most once per message, right after [`Store::send_message`] returns a
    /// fresh send.
    pub async fn set_webhook_message_username(
        &self,
        message_id: MessageId,
        username: &str,
    ) -> anyhow::Result<()> {
        sqlx::query!(
            "INSERT INTO webhook_message_usernames (message_id, username) VALUES (?, ?)",
            message_id,
            username
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// The `username` label stored against `message_id`, or `None` if it was
    /// posted with none. No caller reads this yet outside tests; the read
    /// path that surfaces it is stage 3's job (see this module's own doc).
    pub async fn webhook_message_username(
        &self,
        message_id: MessageId,
    ) -> anyhow::Result<Option<String>> {
        let username = sqlx::query_scalar!(
            "SELECT username FROM webhook_message_usernames WHERE message_id = ?",
            message_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(username)
    }

    /// Revokes a webhook by deleting its row outright. There is no session
    /// and no socket to also close, so the row going away is the whole of
    /// it - simpler than [`Store::revoke_bot`], and immediate the same way.
    /// The principal's `users` row survives, so anything it already posted
    /// stays attributed. Returns `false` if no webhook by that id exists.
    pub async fn revoke_webhook(&self, webhook_id: WebhookId) -> anyhow::Result<bool> {
        let affected = sqlx::query!("DELETE FROM webhooks WHERE id = ?", webhook_id)
            .execute(&self.pool)
            .await?
            .rows_affected();
        Ok(affected > 0)
    }
}
