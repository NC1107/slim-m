// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A bot's own registered prefix and command palette: advertisement, not
//! interactions. See docs/decisions/0031-bot-command-registration.md.
//!
//! The server never runs a bot command - a bot registers what it answers to,
//! the composer offers it in the `/` menu, and picking a row inserts the
//! bot's own prefix and keyword as plain text, the exact message a bot's own
//! process already parses today. Nothing here is an execution path; it is
//! only what a client reads to decide what to offer, and what a bot's own
//! profile shows about it.
//!
//! [`Store::set_bot_commands`] is a bulk overwrite, on purpose: a bot
//! re-registers its complete set on every connect (Discord's own shape), so
//! a command dropped from its own source actually disappears rather than
//! lingering as a stale advertisement nobody will ever answer.

use std::collections::HashMap;

use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;

use super::{Store, now_ms};

/// Caps kept in prose in `schema/openapi.yaml` per this project's convention
/// for parameter constraints the additive-schema gate cannot express.
pub const MAX_BOT_COMMANDS: usize = 50;
pub const MAX_BOT_PREFIX_LEN: usize = 16;
pub const MAX_BOT_COMMAND_NAME_LEN: usize = 32;
pub const MAX_BOT_COMMAND_DESCRIPTION_LEN: usize = 100;
pub const MAX_BOT_COMMAND_USAGE_LEN: usize = 80;

/// Trigger characters the composer already assigns meaning to (module/app
/// commands and mentions, role mentions, emoji shortcodes), so a bot may
/// never claim one as its own prefix - a bot answering to `/` could shadow a
/// module's own `/name` command at send time, since only the module list is
/// ever intercepted before a message posts.
pub const RESERVED_BOT_PREFIXES: [&str; 3] = ["/", "@", ":"];

/// One command a bot advertises.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BotCommand {
    pub name: String,
    pub description: String,
    pub usage: Option<String>,
    /// A single [`Permissions`] bit, same encoding as `GET
    /// /channels/{channelId}/permissions`. A hint the composer uses to hide
    /// this row from a caller who lacks it in the current channel - never
    /// enforced against the plain message the bot goes on to receive, so the
    /// bot must still check independently before acting on it.
    pub permission: Option<i64>,
}

/// A bot's whole registration: its own prefix, plus every command it
/// currently advertises, in the order it declared them.
#[derive(Debug, Clone)]
pub struct BotCommandRegistration {
    pub prefix: String,
    pub commands: Vec<BotCommand>,
}

/// Why a registration attempt was refused.
#[derive(Debug)]
pub enum SetBotCommandsError {
    TooManyCommands,
    InvalidPrefix(&'static str),
    InvalidCommand(&'static str),
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for SetBotCommandsError {
    fn from(err: sqlx::Error) -> Self {
        SetBotCommandsError::Internal(err.into())
    }
}

/// One command a viewer of a particular channel may currently be offered,
/// with the bot that registered it - the composer's own row shape, before the
/// client turns it into an [`crate::store::Store`]-agnostic suggestion.
#[derive(Debug, Clone)]
pub struct VisibleBotCommand {
    pub bot_user_id: UserId,
    pub bot_username: String,
    pub bot_display_name: String,
    pub prefix: String,
    pub command: BotCommand,
}

/// A prefix must be short, whitespace-free, and not one of the composer's own
/// reserved triggers.
fn validate_bot_prefix(prefix: &str) -> Result<(), &'static str> {
    if prefix.is_empty() || prefix.chars().count() > MAX_BOT_PREFIX_LEN {
        return Err("a bot's prefix must be 1 to 16 characters");
    }
    if prefix.chars().any(char::is_whitespace) {
        return Err("a bot's prefix must not contain whitespace");
    }
    if RESERVED_BOT_PREFIXES.contains(&prefix) {
        return Err("a bot's prefix must not be one of the reserved composer triggers / @ :");
    }
    Ok(())
}

/// A command name is a bare keyword (no leading punctuation - the prefix
/// supplies that), matching the charset a module's own slash-command name
/// already keeps to.
fn validate_bot_command(command: &BotCommand) -> Result<(), &'static str> {
    if command.name.is_empty() || command.name.chars().count() > MAX_BOT_COMMAND_NAME_LEN {
        return Err("a command name must be 1 to 32 characters");
    }
    if !command
        .name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return Err("a command name may only hold letters, digits, - and _");
    }
    if command.description.is_empty()
        || command.description.chars().count() > MAX_BOT_COMMAND_DESCRIPTION_LEN
    {
        return Err("a command description must be 1 to 100 characters");
    }
    if let Some(usage) = &command.usage
        && usage.chars().count() > MAX_BOT_COMMAND_USAGE_LEN
    {
        return Err("a command's usage hint must be at most 80 characters");
    }
    if let Some(bit) = command.permission {
        let perm = Permissions::from_bits(bit);
        let single_bit = bit > 0 && (bit & (bit - 1)) == 0;
        if !single_bit || !Permissions::ALL.contains(perm) {
            return Err("a command's permission must be exactly one known permission bit");
        }
    }
    Ok(())
}

impl Store {
    /// Replaces a bot's whole registration - its prefix and its full command
    /// list - in one transaction. Rejects the set outright rather than
    /// partially applying it: a bot that fixes one bad command and resends
    /// gets the same all-or-nothing bulk overwrite Discord's own registration
    /// gives, so it never ends up with half its old set and half its new one.
    pub async fn set_bot_commands(
        &self,
        bot_user_id: UserId,
        prefix: &str,
        commands: &[BotCommand],
    ) -> Result<(), SetBotCommandsError> {
        validate_bot_prefix(prefix).map_err(SetBotCommandsError::InvalidPrefix)?;
        if commands.len() > MAX_BOT_COMMANDS {
            return Err(SetBotCommandsError::TooManyCommands);
        }
        let mut seen = std::collections::HashSet::with_capacity(commands.len());
        for command in commands {
            validate_bot_command(command).map_err(SetBotCommandsError::InvalidCommand)?;
            if !seen.insert(command.name.to_lowercase()) {
                return Err(SetBotCommandsError::InvalidCommand(
                    "a bot cannot register the same command name twice",
                ));
            }
        }

        let now = now_ms();
        let mut tx = self.pool.begin().await?;
        sqlx::query!(
            "INSERT INTO bot_command_registrations (bot_user_id, prefix, updated_at)
             VALUES (?, ?, ?)
             ON CONFLICT (bot_user_id) DO UPDATE SET prefix = excluded.prefix, updated_at = excluded.updated_at",
            bot_user_id,
            prefix,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "DELETE FROM bot_commands WHERE bot_user_id = ?",
            bot_user_id
        )
        .execute(&mut *tx)
        .await?;
        for (position, command) in commands.iter().enumerate() {
            let position = position as i64;
            sqlx::query!(
                "INSERT INTO bot_commands (bot_user_id, name, description, usage, permission, position)
                 VALUES (?, ?, ?, ?, ?, ?)",
                bot_user_id,
                command.name,
                command.description,
                command.usage,
                command.permission,
                position
            )
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    /// A bot's whole current registration, unfiltered by channel or by any
    /// caller's own permissions - what a profile popover shows about the bot
    /// itself, not what one particular viewer may currently be offered in one
    /// particular channel (see [`Store::visible_bot_commands`] for that).
    /// `None` when the bot has never registered anything, including for a
    /// non-bot or unknown id.
    pub async fn bot_commands(
        &self,
        bot_user_id: UserId,
    ) -> anyhow::Result<Option<BotCommandRegistration>> {
        let Some(reg) = sqlx::query!(
            "SELECT prefix FROM bot_command_registrations WHERE bot_user_id = ?",
            bot_user_id
        )
        .fetch_optional(&self.pool)
        .await?
        else {
            return Ok(None);
        };
        let rows = sqlx::query!(
            "SELECT name, description, usage, permission
             FROM bot_commands WHERE bot_user_id = ? ORDER BY position ASC",
            bot_user_id
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(Some(BotCommandRegistration {
            prefix: reg.prefix,
            commands: rows
                .into_iter()
                .map(|r| BotCommand {
                    name: r.name,
                    description: r.description,
                    usage: r.usage,
                    permission: r.permission,
                })
                .collect(),
        }))
    }

    /// Every command a caller may currently be offered in `channel_id`,
    /// across every bot - the discovery list behind the `/` menu's bot half.
    ///
    /// A bot's whole registration is left out unless its token is live and it
    /// is still a member of the Space (so a revoked or removed bot's commands
    /// vanish here with no separate cleanup path, the same live-query answer
    /// [`Store::list_bots`] already gives) and it itself currently holds
    /// VIEW_CHANNEL in this channel - a bot with no access to a channel must
    /// not advertise itself there any more than a person would be shown
    /// mentioning someone who cannot read it. A single command whose declared
    /// `permission` bit is missing from `caller_permissions` is left out on
    /// its own, not the whole bot, since one bot can mix gated and open
    /// commands.
    pub async fn visible_bot_commands(
        &self,
        channel_id: ChannelId,
        caller_permissions: Permissions,
    ) -> anyhow::Result<Vec<VisibleBotCommand>> {
        let rows = sqlx::query!(
            r#"SELECT u.id AS "bot_user_id!: UserId", u.username, u.display_name,
                      r.prefix, c.name, c.description, c.usage, c.permission
               FROM bot_command_registrations r
               JOIN users u ON u.id = r.bot_user_id
               JOIN bot_commands c ON c.bot_user_id = r.bot_user_id
               JOIN bot_tokens t ON t.bot_user_id = u.id AND t.revoked_at IS NULL
               WHERE u.is_bot = 1 AND u.deleted_at IS NULL
                 AND NOT EXISTS (SELECT 1 FROM space_removals sr WHERE sr.user_id = u.id)
               ORDER BY r.prefix ASC, c.position ASC"#,
        )
        .fetch_all(&self.pool)
        .await?;

        let mut can_view: HashMap<UserId, bool> = HashMap::new();
        let mut visible = Vec::new();
        for row in rows {
            if let Some(bit) = row.permission
                && !caller_permissions.contains(Permissions::from_bits(bit))
            {
                continue;
            }
            let allowed = match can_view.get(&row.bot_user_id) {
                Some(allowed) => *allowed,
                None => {
                    let allowed = self
                        .permissions_in_channel(row.bot_user_id, channel_id)
                        .await?
                        .contains(Permissions::VIEW_CHANNEL);
                    can_view.insert(row.bot_user_id, allowed);
                    allowed
                }
            };
            if !allowed {
                continue;
            }
            visible.push(VisibleBotCommand {
                bot_user_id: row.bot_user_id,
                bot_username: row.username,
                bot_display_name: row.display_name,
                prefix: row.prefix,
                command: BotCommand {
                    name: row.name,
                    description: row.description,
                    usage: row.usage,
                    permission: row.permission,
                },
            });
        }
        Ok(visible)
    }
}
