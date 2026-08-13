// SPDX-License-Identifier: AGPL-3.0-only
//! Unit tests for `gifs.rs` itself - construction, error mapping, and the
//! filename extension helper. The token cache has its own tests beside it in
//! `cache.rs`. The full search-pick-select round trip against a fake
//! provider lives in `tests/gif_picker.rs` instead, since that needs a real
//! router and a real fake HTTP server neither of which belongs in a unit test.

use super::*;

#[test]
fn gif_error_maps_to_the_documented_status_codes() {
    assert!(matches!(
        ApiError::from(GifError::NotConfigured),
        ApiError::NotConfigured(_)
    ));
    assert!(matches!(
        ApiError::from(GifError::Unavailable),
        ApiError::Unavailable
    ));
}

#[test]
fn extension_matches_the_two_sniffable_gif_content_types() {
    assert_eq!(extension_for("image/gif"), "gif");
    assert_eq!(extension_for("image/webp"), "webp");
}

#[test]
fn new_stays_disabled_when_neither_setting_is_present() {
    let gifs = GifSearch::new(&Config::default()).expect("no provider is not an error");
    assert!(!gifs.is_enabled());
}

/// Only one of the pair being set is the same as neither: a self-host that
/// half-configures this by accident gets no GIF search rather than a
/// confusing runtime failure the first time it is used.
#[test]
fn new_stays_disabled_with_only_a_provider_or_only_a_key() {
    let only_provider = GifSearch::new(&Config {
        gif_provider: Some("tenor".to_owned()),
        ..Config::default()
    })
    .expect("half-configured is not an error");
    assert!(!only_provider.is_enabled());

    let only_key = GifSearch::new(&Config {
        gif_api_key: Some("k".to_owned()),
        ..Config::default()
    })
    .expect("half-configured is not an error");
    assert!(!only_key.is_enabled());
}

#[test]
fn new_fails_at_startup_on_an_unrecognized_provider_name() {
    let result = GifSearch::new(&Config {
        gif_provider: Some("giphy".to_owned()),
        gif_api_key: Some("k".to_owned()),
        ..Config::default()
    });
    assert!(result.is_err());
}

#[test]
fn new_is_case_insensitive_and_enables_on_either_recognized_name() {
    for name in ["tenor", "TENOR", "Klipy"] {
        let gifs = GifSearch::new(&Config {
            gif_provider: Some(name.to_owned()),
            gif_api_key: Some("k".to_owned()),
            ..Config::default()
        })
        .unwrap_or_else(|_| panic!("{name} is a recognized provider"));
        assert!(gifs.is_enabled());
    }
}
