// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Idempotent state derived from LiveKit webhooks, so a retried or duplicate
//! delivery cannot double-publish a join, leave or screen-share change.
//!
//! Mirrors `voice::heartbeat`'s `CallHeartbeats`: a lock-held check-and-write
//! per transition rather than a separate read then write, for the same
//! reason - two webhooks for the same transition racing each other must
//! still agree on exactly one of them being the one that publishes. See
//! `docs/decisions/0032-voice-participant-webhooks.md`.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, MutexGuard};

use crate::ids::{ChannelId, UserId};

use super::VoiceService;

#[derive(Default)]
struct ParticipantState {
    /// Sids of currently-published screen-share-sourced tracks. A screen
    /// share with audio publishes two tracks, so "is sharing" is "this set
    /// is non-empty", not "a track was published".
    screen_share_tracks: HashSet<String>,
}

type Key = (ChannelId, UserId);

/// Tracks who a LiveKit webhook has told us is on a call, and whether they
/// are sharing their screen right now.
#[derive(Clone, Default)]
pub struct RoomLiveState {
    state: Arc<Mutex<HashMap<Key, ParticipantState>>>,
}

impl RoomLiveState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Records a join, reporting whether this is a real transition - a
    /// duplicate `participant_joined` webhook for someone already known must
    /// not republish.
    pub fn mark_joined(&self, channel_id: ChannelId, user_id: UserId) -> bool {
        match lock(&self.state).entry((channel_id, user_id)) {
            std::collections::hash_map::Entry::Vacant(entry) => {
                entry.insert(ParticipantState::default());
                true
            }
            std::collections::hash_map::Entry::Occupied(_) => false,
        }
    }

    /// Forgets a participant entirely, reporting whether they were known at
    /// all - a duplicate `participant_left` for someone already gone must
    /// not republish.
    pub fn mark_left(&self, channel_id: ChannelId, user_id: UserId) -> bool {
        lock(&self.state).remove(&(channel_id, user_id)).is_some()
    }

    /// Records a screen-share track publish, reporting `true` only when this
    /// is the track that made the participant start sharing - a second
    /// screen-share track (video's own audio) publishing while the first is
    /// still up is not a fresh "started sharing".
    ///
    /// Auto-vivifies the participant if a `track_published` webhook somehow
    /// outraces its `participant_joined`: LiveKit does not order these two
    /// unqueued deliveries against each other, and treating a track from an
    /// unknown participant as evidence they are present is safer than
    /// dropping it and never learning they are sharing at all.
    pub fn track_published(&self, channel_id: ChannelId, user_id: UserId, track_sid: &str) -> bool {
        let mut state = lock(&self.state);
        let participant = state.entry((channel_id, user_id)).or_default();
        let was_sharing = !participant.screen_share_tracks.is_empty();
        participant.screen_share_tracks.insert(track_sid.to_owned());
        !was_sharing
    }

    /// Records a screen-share track unpublish, reporting `true` only when
    /// this was the participant's last screen-share track.
    pub fn track_unpublished(
        &self,
        channel_id: ChannelId,
        user_id: UserId,
        track_sid: &str,
    ) -> bool {
        let mut state = lock(&self.state);
        let Some(participant) = state.get_mut(&(channel_id, user_id)) else {
            return false;
        };
        participant.screen_share_tracks.remove(track_sid);
        participant.screen_share_tracks.is_empty()
    }
}

fn lock(
    state: &Mutex<HashMap<Key, ParticipantState>>,
) -> MutexGuard<'_, HashMap<Key, ParticipantState>> {
    match state.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

impl VoiceService {
    /// The shared, cloneable live-state tracker; see this module's own doc.
    pub fn live_state(&self) -> RoomLiveState {
        self.live_state.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn uid() -> UserId {
        UserId::generate()
    }

    fn cid() -> ChannelId {
        ChannelId::generate()
    }

    #[test]
    fn a_first_join_is_a_real_transition() {
        let state = RoomLiveState::new();
        assert!(state.mark_joined(cid(), uid()));
    }

    #[test]
    fn a_duplicate_join_webhook_does_not_republish() {
        let state = RoomLiveState::new();
        let (channel, user) = (cid(), uid());
        assert!(state.mark_joined(channel, user));
        assert!(!state.mark_joined(channel, user));
    }

    #[test]
    fn leaving_someone_unknown_reports_no_transition() {
        let state = RoomLiveState::new();
        assert!(!state.mark_left(cid(), uid()));
    }

    #[test]
    fn a_duplicate_leave_webhook_does_not_republish() {
        let state = RoomLiveState::new();
        let (channel, user) = (cid(), uid());
        state.mark_joined(channel, user);
        assert!(state.mark_left(channel, user));
        assert!(!state.mark_left(channel, user));
    }

    #[test]
    fn the_first_screen_share_track_starts_sharing() {
        let state = RoomLiveState::new();
        let (channel, user) = (cid(), uid());
        state.mark_joined(channel, user);
        assert!(state.track_published(channel, user, "track-video"));
    }

    #[test]
    fn a_second_screen_share_track_is_not_a_fresh_start() {
        let state = RoomLiveState::new();
        let (channel, user) = (cid(), uid());
        state.mark_joined(channel, user);
        assert!(state.track_published(channel, user, "track-video"));
        assert!(!state.track_published(channel, user, "track-audio"));
    }

    #[test]
    fn sharing_stops_only_once_every_screen_share_track_is_gone() {
        let state = RoomLiveState::new();
        let (channel, user) = (cid(), uid());
        state.mark_joined(channel, user);
        state.track_published(channel, user, "track-video");
        state.track_published(channel, user, "track-audio");

        assert!(
            !state.track_unpublished(channel, user, "track-video"),
            "the audio track is still up"
        );
        assert!(
            state.track_unpublished(channel, user, "track-audio"),
            "that was the last screen-share track"
        );
    }

    #[test]
    fn unpublishing_a_track_for_someone_unknown_reports_no_transition() {
        let state = RoomLiveState::new();
        assert!(!state.track_unpublished(cid(), uid(), "track-video"));
    }

    #[test]
    fn a_track_published_before_any_join_webhook_still_counts() {
        let state = RoomLiveState::new();
        let (channel, user) = (cid(), uid());
        assert!(state.track_published(channel, user, "track-video"));
    }
}
