// SPDX-License-Identifier: AGPL-3.0-only
//! Who gets woken for a message, and why each exclusion is there.
//!
//! Its own module rather than three steps inside [`super::deliver`]'s
//! fire-and-forget task: this is the whole authorization decision on the push
//! path, and a task that reports to nothing but the process log cannot be
//! tested. `tests/blocking_reach.rs` drives it directly.

use std::collections::HashSet;

use crate::ids::{ChannelId, UserId};
use crate::store::Store;

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
/// through unchanged.
pub async fn message_recipients(
    store: &Store,
    channel_id: ChannelId,
    author_id: UserId,
    content: &str,
) -> anyhow::Result<Vec<UserId>> {
    // Push registrations first, permissions second; see the note above.
    let candidates = store.users_with_push_devices().await?;
    let blockers = store.blockers_of(author_id).await?;
    let candidates: Vec<UserId> = candidates
        .into_iter()
        .filter(|user_id| *user_id != author_id && !blockers.contains(user_id))
        .collect();
    let viewers = store.viewers_among(channel_id, &candidates).await?;
    narrow_for_thread(store, channel_id, content, viewers).await
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
/// plus everyone who has posted in the thread) unioned with anybody `content`
/// `@`-mentions, each still intersected with `viewers` so this can only ever
/// remove somebody from the set already permission-checked above, never add a
/// view nobody granted.
async fn narrow_for_thread(
    store: &Store,
    channel_id: ChannelId,
    content: &str,
    viewers: Vec<UserId>,
) -> anyhow::Result<Vec<UserId>> {
    let Some(parent) = store.thread_parent(channel_id).await? else {
        return Ok(viewers);
    };
    let mut audience = store
        .thread_participants(channel_id, parent.parent_message_id)
        .await?;
    let mentioned: Vec<String> = mentioned_usernames(content).into_iter().collect();
    if !mentioned.is_empty() {
        audience.extend(store.user_ids_for_usernames(&mentioned).await?);
    }
    Ok(viewers
        .into_iter()
        .filter(|user_id| audience.contains(user_id))
        .collect())
}

/// The distinct `@name` runs in `content`, over the same `[A-Za-z0-9_]+`
/// charset `message_inline.dart`'s `_mentionPattern` renders as a mention
/// chip, so a push reaches exactly the mentions a reader would actually see
/// highlighted. Hand-rolled rather than a `regex` dependency, the same call
/// this codebase already made for its client-side markdown grammar.
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
        let mut end = start;
        while end < bytes.len() && (bytes[end].is_ascii_alphanumeric() || bytes[end] == b'_') {
            end += 1;
        }
        if end > start {
            names.insert(content[start..end].to_owned());
        }
        i = end.max(start);
    }
    names
}

#[cfg(test)]
mod tests {
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
}
