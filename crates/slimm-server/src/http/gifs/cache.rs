// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The token cache described in the parent module's own doc comment: an
//! opaque, bounded, TTL'd map from a search-minted token to the two real
//! upstream URLs it stands in for. Split out to keep `gifs.rs` under the
//! review budget.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

use uuid::Uuid;

use crate::store::now_ms;

use super::provider;

/// How long a minted token stays redeemable. Generous next to how long a
/// person spends browsing one search's results, since nothing here re-mints
/// a token on expiry - it just goes back to "search again".
const CACHE_TTL_MS: i64 = 15 * 60 * 1000;

/// Most tokens held at once, across every caller. Bounds memory against a
/// sustained flood the way [`crate::ratelimit`]'s own bucket map already
/// bounds itself; past it, the oldest half is evicted in one pass rather
/// than one token at a time, so a sweep triggered by a flood does not itself
/// become the flood's cost.
const MAX_CACHE_ENTRIES: usize = 5_000;

/// Handed a search hit's own [`provider::ProviderGif`], picks a fresh opaque
/// token, caches the two real URLs behind it, and returns the wire shape a
/// client sees.
struct CachedGif {
    preview_url: String,
    full_url: String,
    inserted_at: i64,
}

/// A plain `Mutex<HashMap<..>>`, the same shape
/// [`crate::push::debounce::Debounce`] already uses for an in-process,
/// best-effort table with no need for a dedicated cache crate.
pub(super) struct Cache {
    entries: Mutex<HashMap<String, CachedGif>>,
}

impl Cache {
    pub(super) fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    /// Mints and caches a fresh token for `gif`, sweeping expired entries
    /// first and, only if the map is still over [`MAX_CACHE_ENTRIES`] after
    /// that, evicting the oldest half in one pass.
    pub(super) fn insert(&self, gif: &provider::ProviderGif) -> String {
        let token = Uuid::now_v7().to_string();
        let now = now_ms();
        let mut guard = self.lock();
        guard.retain(|_, cached| now - cached.inserted_at < CACHE_TTL_MS);
        if guard.len() >= MAX_CACHE_ENTRIES {
            let mut by_age: Vec<(String, i64)> = guard
                .iter()
                .map(|(key, cached)| (key.clone(), cached.inserted_at))
                .collect();
            by_age.sort_by_key(|(_, at)| *at);
            for (key, _) in by_age.into_iter().take(guard.len() / 2) {
                guard.remove(&key);
            }
        }
        guard.insert(
            token.clone(),
            CachedGif {
                preview_url: gif.preview_url.clone(),
                full_url: gif.full_url.clone(),
                inserted_at: now,
            },
        );
        token
    }

    pub(super) fn preview_url(&self, token: &str) -> Option<String> {
        self.lock()
            .get(token)
            .map(|cached| cached.preview_url.clone())
    }

    pub(super) fn full_url(&self, token: &str) -> Option<String> {
        self.lock().get(token).map(|cached| cached.full_url.clone())
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<String, CachedGif>> {
        match self.entries.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(preview: &str, full: &str, ago_ms: i64) -> CachedGif {
        CachedGif {
            preview_url: preview.to_owned(),
            full_url: full.to_owned(),
            inserted_at: now_ms() - ago_ms,
        }
    }

    fn hit(preview: &str, full: &str) -> provider::ProviderGif {
        provider::ProviderGif {
            title: "a title".to_owned(),
            preview_url: preview.to_owned(),
            full_url: full.to_owned(),
            width: 100,
            height: 100,
        }
    }

    #[test]
    fn a_fresh_token_resolves_both_urls() {
        let cache = Cache::new();
        let token = cache.insert(&hit("https://p", "https://f"));
        assert_eq!(cache.preview_url(&token).as_deref(), Some("https://p"));
        assert_eq!(cache.full_url(&token).as_deref(), Some("https://f"));
    }

    #[test]
    fn an_unknown_token_resolves_nothing() {
        let cache = Cache::new();
        assert_eq!(cache.preview_url("nonexistent"), None);
        assert_eq!(cache.full_url("nonexistent"), None);
    }

    /// The sweep runs on every insert, so planting an already-expired entry
    /// directly and then inserting a fresh one proves the expired one is
    /// gone, without waiting out the real TTL.
    #[test]
    fn an_expired_entry_is_swept_on_the_next_insert() {
        let cache = Cache::new();
        cache.entries.lock().unwrap().insert(
            "stale".to_owned(),
            fixture("https://p", "https://f", CACHE_TTL_MS + 1),
        );
        cache.insert(&hit("https://p2", "https://f2"));
        assert_eq!(cache.preview_url("stale"), None);
    }

    /// Past the ceiling, the oldest half goes, not the newest - proven by
    /// planting one old and one fresh entry directly, filling the map to the
    /// ceiling with old ones, then inserting once more and checking survivors
    /// by age rather than by count alone.
    #[test]
    fn past_the_ceiling_the_oldest_half_is_evicted_not_the_newest() {
        let cache = Cache::new();
        {
            let mut guard = cache.entries.lock().unwrap();
            for i in 0..MAX_CACHE_ENTRIES {
                // Strictly increasing age, oldest first: index alone tells survivor from evicted.
                guard.insert(
                    format!("old-{i}"),
                    fixture("https://p", "https://f", (MAX_CACHE_ENTRIES - i) as i64),
                );
            }
        }
        cache.insert(&hit("https://newest-p", "https://newest-f"));
        let guard = cache.entries.lock().unwrap();
        assert!(guard.len() <= MAX_CACHE_ENTRIES);
        // The oldest planted entry is gone; the freshest of the old batch survives.
        assert!(!guard.contains_key("old-0"));
        assert!(guard.contains_key(&format!("old-{}", MAX_CACHE_ENTRIES - 1)));
    }
}
