// SPDX-License-Identifier: AGPL-3.0-only
//! Who gets woken for a message, and why each exclusion is there.
//!
//! Its own module rather than three steps inside [`super::deliver::deliver`]'s
//! fire-and-forget task: this is the whole authorization decision on the push
//! path, and a task that reports to nothing but the process log cannot be
//! tested. `tests/blocking_reach.rs` drives it directly.

use std::collections::HashSet;

use crate::ids::{ChannelId, UserId};
use crate::notifications::{NotificationPreference, minute_of_day_utc};
use crate::permissions::Permissions;
use crate::presence::PresenceTracker;
use crate::store::Store;

/// The reserved mention naming every candidate viewer, never a real
/// username: `validate_username` (`http/auth.rs`) refuses to register it for
/// exactly this reason, so `@everyone` can never collide with an account.
const EVERYONE_MENTION: &str = "everyone";

/// The reserved mention naming every candidate viewer who is currently
/// connected - the same reservation, and the same refusal, as
/// [`EVERYONE_MENTION`].
const HERE_MENTION: &str = "here";

/// Who should be woken for `content` in `channel_id`, written by `author_id`.
///
/// The set is built from who could receive a push at all, then filtered by view
/// permission, rather than evaluating permissions for every live user and then
/// asking which of them have a device. Both orders give the same recipients, but
/// this one costs a single indexed query on a deployment where nobody has
/// registered for push, instead of a full permission evaluation per user on
/// every message sent. The view check itself is not an optimization to skip: a
/// recipient who cannot see the channel must never be told a message landed in
/// it.
///
/// The author is dropped, and so is anybody who has blocked them. Push is the
/// one surface a client-side block filter cannot reach - the notification is on
/// the device before any filter runs - and a phone that buzzes for a message the
/// app then hides is worse than no filtering, since it reports exactly when the
/// blocked person spoke. It stays a view choice rather than a moderation action:
/// the message is delivered to everybody else and the author is never told.
///
/// When `channel_id` is a thread's own channel, [`narrow_for_thread`] further
/// cuts this down to the thread's own audience; every other channel passes
/// through unchanged. [`narrow_for_notification_preference`] runs last, over
/// whatever survived both of the above: each recipient's own
/// [`NotificationPreference`] is the final word on whether this particular
/// message is worth waking them for, the same "read where the audience is
/// computed" choke point blocking already uses above, not a filter a client
/// applies after a device has already buzzed.
///
/// `presence` answers `@here`'s "currently connected" question; see
/// [`resolved_mentions`].
pub async fn message_recipients(
    store: &Store,
    channel_id: ChannelId,
    author_id: UserId,
    content: &str,
    presence: &PresenceTracker,
) -> anyhow::Result<Vec<UserId>> {
    // Push registrations first, permissions second; see the note above.
    let candidates = store.users_with_push_devices().await?;
    let blockers = store.blockers_of(author_id).await?;
    let candidates: Vec<UserId> = candidates
        .into_iter()
        .filter(|user_id| *user_id != author_id && !blockers.contains(user_id))
        .collect();
    let viewers = store.viewers_among(channel_id, &candidates).await?;
    let mentioned =
        resolved_mentions(store, channel_id, author_id, content, &viewers, presence).await?;
    let viewers = narrow_for_thread(store, channel_id, &mentioned, viewers).await?;
    narrow_for_notification_preference(store, channel_id, &mentioned, viewers).await
}

/// The distinct accounts a message's mentions resolve to - shared by
/// [`narrow_for_thread`] and [`narrow_for_notification_preference`] so a
/// message that is both a thread reply and has mentions only pays for the
/// resolution once.
///
/// [`EVERYONE_MENTION`] and [`HERE_MENTION`] are pulled out of the ordinary
/// `@username` set before it goes to [`Store::user_ids_for_usernames`] -
/// neither is ever a real account, so asking the username table about them
/// would only ever answer "no such user". Each expands against `viewers`
/// (already the candidates this message's channel and blocking already
/// allow) rather than every account in the deployment, and only once the
/// author is confirmed to hold [`Permissions::MENTION_EVERYONE`] in
/// `channel_id` - checked here, at the one place a mass mention turns into an
/// actual wake, rather than by refusing the send: a caller without the bit
/// can still type the word, it just pings nobody extra, the same forgiving
/// shape an ordinary `@nobody` already has. `@everyone` expands to every
/// viewer; `@here` narrows that to whoever `presence` reports connected right
/// now, which is what distinguishes the two words at all.
async fn resolved_mentions(
    store: &Store,
    channel_id: ChannelId,
    author_id: UserId,
    content: &str,
    viewers: &[UserId],
    presence: &PresenceTracker,
) -> anyhow::Result<HashSet<UserId>> {
    let mut names = mentioned_usernames(content);
    let mentions_everyone = names.remove(EVERYONE_MENTION);
    let mentions_here = names.remove(HERE_MENTION);

    let mut resolved: HashSet<UserId> = if names.is_empty() {
        HashSet::new()
    } else {
        let names: Vec<String> = names.into_iter().collect();
        store
            .user_ids_for_usernames(&names)
            .await?
            .into_iter()
            .collect()
    };

    if (mentions_everyone || mentions_here)
        && store
            .has_permission(author_id, channel_id, Permissions::MENTION_EVERYONE)
            .await?
    {
        if mentions_everyone {
            resolved.extend(viewers.iter().copied());
        } else {
            resolved.extend(
                viewers
                    .iter()
                    .copied()
                    .filter(|user_id| presence.is_connected(*user_id)),
            );
        }
    }

    Ok(resolved)
}

/// Narrows `viewers` to a thread's own audience, for a reply into a thread's
/// own channel; every other channel is returned unchanged.
///
/// `viewers` already answers "who may see this", by the same
/// [`Store::permission_channel`] resolution to the parent every other check
/// uses - correct for authorization, and untouched here. What is wrong for a
/// thread is treating that whole parent-channel audience as who should be
/// *woken* by one reply in what may be a two-person side conversation. The
/// audience is [`Store::thread_participants`] (the parent message's author
/// plus everyone who has posted in the thread) unioned with `mentioned`
/// (already resolved by the caller), each still intersected with `viewers` so
/// this can only ever remove somebody from the set already permission-checked
/// above, never add a view nobody granted.
async fn narrow_for_thread(
    store: &Store,
    channel_id: ChannelId,
    mentioned: &HashSet<UserId>,
    viewers: Vec<UserId>,
) -> anyhow::Result<Vec<UserId>> {
    let Some(parent) = store.thread_parent(channel_id).await? else {
        return Ok(viewers);
    };
    let mut audience = store
        .thread_participants(channel_id, parent.parent_message_id)
        .await?;
    audience.extend(mentioned.iter().copied());
    Ok(viewers
        .into_iter()
        .filter(|user_id| audience.contains(user_id))
        .collect())
}

/// Narrows `viewers` by each recipient's own *effective* [`NotificationPreference`]
/// for `channel_id`: that recipient's own per-channel override
/// (`store/channel_notification_prefs.rs`) if they have set one for this
/// channel, else their account-wide default. [`NotificationPreference::Nothing`]
/// drops them unconditionally, including from a DM; [`NotificationPreference::Mentions`]
/// keeps them only if `mentioned` names them or `channel_id` resolves to a DM
/// (see [`Store::channel_notifies_as_dm`] for why a DM counts - somebody
/// messaging this account there is addressing them directly, the same as a
/// mention); and [`NotificationPreference::Everything`] passes everyone
/// through unfiltered, which is what every account already got before either
/// preference existed. A channel override always wins over the account
/// default, in both directions: a `nothing`/`mentions` override silences a
/// channel an `everything` default would have let through, and a `mentions`
/// override still wakes a mentioned recipient whose account default is
/// `nothing`.
///
/// Quiet hours (`store/quiet_hours.rs`) run last, over whatever this
/// resolved: a recipient whose current UTC minute falls inside their own
/// window has their effective preference demoted one notch, from
/// [`NotificationPreference::Everything`] to [`NotificationPreference::Mentions`],
/// before the match above runs - never demoted to [`NotificationPreference::Nothing`],
/// and never touching a recipient whose preference was already `mentions`
/// or `nothing`. That keeps the same hierarchy this function already
/// enforces: a quiet window says "do not wake me for ordinary chatter right
/// now", not "silence even a direct mention", which is what choosing
/// `nothing` outright already means.
async fn narrow_for_notification_preference(
    store: &Store,
    channel_id: ChannelId,
    mentioned: &HashSet<UserId>,
    viewers: Vec<UserId>,
) -> anyhow::Result<Vec<UserId>> {
    if viewers.is_empty() {
        return Ok(viewers);
    }
    let preferences = store
        .channel_notification_preferences(channel_id, &viewers)
        .await?;
    let is_dm = store.channel_notifies_as_dm(channel_id).await?;
    let quiet_hours = store.quiet_hours_for_users(&viewers).await?;
    let current_minute = minute_of_day_utc(crate::store::now_ms());
    Ok(viewers
        .into_iter()
        .filter(|user_id| {
            let mut preference = preferences.get(user_id).copied().unwrap_or_default();
            if preference == NotificationPreference::Everything
                && quiet_hours
                    .get(user_id)
                    .is_some_and(|window| window.contains(current_minute))
            {
                preference = NotificationPreference::Mentions;
            }
            match preference {
                NotificationPreference::Everything => true,
                NotificationPreference::Nothing => false,
                NotificationPreference::Mentions => is_dm || mentioned.contains(user_id),
            }
        })
        .collect())
}

/// The distinct `@name` runs in `content`, over the same greedy charset
/// `message_inline.dart`'s `_mentionPattern` renders as a mention chip -
/// a word character to open, then any run of `[A-Za-z0-9_.-]` - so a push
/// reaches exactly the mentions a reader would actually see highlighted.
/// Trailing `.`/`-` are stripped from each run the same way the client's
/// `_trimMentionEnd` does: `thanks @nick.` at the end of a sentence must
/// resolve to `nick`, not `nick.`, or the mention silently fails to notify
/// anyone. The cost, also paid client-side: a username genuinely ending in
/// `.` or `-` (`validate_username` in `http/auth.rs` allows one) can never
/// be mentioned, since its trailing character always reads as punctuation.
/// Hand-rolled rather than a `regex` dependency, the same call this codebase
/// already made for its client-side markdown grammar.
fn mentioned_usernames(content: &str) -> HashSet<String> {
    let bytes = content.as_bytes();
    let mut names = HashSet::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] != b'@' {
            i += 1;
            continue;
        }
        let start = i + 1;
        if start >= bytes.len() || !is_mention_start(bytes[start]) {
            i += 1;
            continue;
        }
        let mut end = start + 1;
        while end < bytes.len() && is_mention_continuation(bytes[end]) {
            end += 1;
        }
        while end > start + 1 && matches!(bytes[end - 1], b'.' | b'-') {
            end -= 1;
        }
        names.insert(content[start..end].to_owned());
        i = end;
    }
    names
}

fn is_mention_start(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn is_mention_continuation(b: u8) -> bool {
    is_mention_start(b) || matches!(b, b'.' | b'-')
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::mentioned_usernames;

    #[test]
    fn finds_every_distinct_mention_and_nothing_else() {
        let names = mentioned_usernames("hey @alice and @bob, cc @alice again, not an email");
        assert_eq!(names.len(), 2);
        assert!(names.contains("alice"));
        assert!(names.contains("bob"));
    }

    #[test]
    fn a_bare_at_with_nothing_after_it_is_not_a_mention() {
        assert!(mentioned_usernames("look @ this").is_empty());
        assert!(mentioned_usernames("trailing @").is_empty());
    }

    #[test]
    fn a_trailing_full_stop_is_sentence_punctuation_not_part_of_the_name() {
        assert_eq!(mentioned_usernames("thanks @nick."), one("nick"));
    }

    #[test]
    fn a_hyphen_inside_a_name_is_kept_in_full() {
        assert_eq!(mentioned_usernames("see @nick-c"), one("nick-c"));
    }

    fn one(name: &str) -> HashSet<String> {
        HashSet::from([name.to_owned()])
    }

    /// Cross-checked against the exact same cases, on the exact same input
    /// strings, in `client/packages/app/test/
    /// message_inline_mention_charset_test.dart` - editing this function's
    /// charset or trimming rule without a matching client edit fails one side
    /// of that shared table, not both.
    #[test]
    fn the_shared_charset_fixture_agrees_with_message_inline_dart() {
        for case in load_mention_cases() {
            let actual = mentioned_usernames(&case.content);
            let expected: HashSet<String> = case.mentions.into_iter().collect();
            assert_eq!(actual, expected, "content: {:?}", case.content);
        }
    }

    #[derive(serde::Deserialize)]
    struct MentionCase {
        content: String,
        mentions: Vec<String>,
    }

    fn load_mention_cases() -> Vec<MentionCase> {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/mention_charset_cases.json");
        let raw = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("reading {}: {e}", path.display()));
        serde_json::from_str(&raw).expect("mention_charset_cases.json must be valid JSON")
    }
}
