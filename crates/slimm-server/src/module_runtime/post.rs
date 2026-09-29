// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! `message.post` (decision 0023, phase D): a module asks the host to post a
//! message. The host, not this file, decides whether it may - the seam is a
//! [`MessagePoster`] built per run around the invoking user, so the module can
//! neither name nor spoof who it posts as.

use serde::Deserialize;
use serde_json::json;

/// Most posts one module run may attempt, so a single run cannot flood a
/// channel even inside its fuel budget. Cross-run limits live in the poster.
pub const MAX_POSTS_PER_RUN: u32 = 3;

/// Why the host refused a post. The text is shown to the module verbatim, so
/// it must never carry anything the invoking user could not already know.
#[derive(Debug)]
pub struct PostRefused(pub &'static str);

/// Posts on behalf of the user who invoked the module, after the host's own
/// permission, rate and content checks. Returns the new message id.
pub trait MessagePoster: Send + Sync {
    fn post(&self, channel_id: &str, content: &str) -> Result<String, PostRefused>;
}

#[derive(Deserialize)]
struct PostRequest {
    #[serde(default)]
    channel_id: Option<String>,
    #[serde(default)]
    content: Option<String>,
}

/// Dispatches one `message.post` request, returning the UTF-8 JSON response.
/// `posts_remaining` is this run's budget, spent per attempt.
pub fn handle(poster: &dyn MessagePoster, posts_remaining: &mut u32, request: &[u8]) -> Vec<u8> {
    if *posts_remaining == 0 {
        return refusal("message.post budget for this run is exhausted");
    }
    *posts_remaining -= 1;
    let Ok(req) = serde_json::from_slice::<PostRequest>(request) else {
        return refusal("malformed message.post request");
    };
    let (Some(channel_id), Some(content)) = (req.channel_id, req.content) else {
        return refusal("message.post needs a channel_id and content");
    };
    match poster.post(&channel_id, &content) {
        Ok(message_id) => serde_json::to_vec(&json!({ "ok": true, "message_id": message_id }))
            .unwrap_or_else(|_| br#"{"ok":true}"#.to_vec()),
        Err(PostRefused(reason)) => refusal(reason),
    }
}

fn refusal(message: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({ "ok": false, "error": message }))
        .unwrap_or_else(|_| br#"{"ok":false,"error":"host error"}"#.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixed(Result<String, &'static str>);

    impl MessagePoster for Fixed {
        fn post(&self, _: &str, _: &str) -> Result<String, PostRefused> {
            self.0.clone().map_err(PostRefused)
        }
    }

    fn text(bytes: Vec<u8>) -> String {
        String::from_utf8(bytes).unwrap()
    }

    #[test]
    fn a_post_returns_the_message_id() {
        let mut left = MAX_POSTS_PER_RUN;
        let out = text(handle(
            &Fixed(Ok("id-1".into())),
            &mut left,
            br#"{"channel_id":"c","content":"hi"}"#,
        ));
        assert!(out.contains(r#""message_id":"id-1""#), "{out}");
    }

    #[test]
    fn a_host_refusal_reaches_the_module_as_a_clean_error() {
        let mut left = MAX_POSTS_PER_RUN;
        let out = text(handle(
            &Fixed(Err("nope")),
            &mut left,
            br#"{"channel_id":"c","content":"hi"}"#,
        ));
        assert!(
            out.contains(r#""ok":false"#) && out.contains("nope"),
            "{out}"
        );
    }

    #[test]
    fn the_per_run_budget_is_spent_even_by_a_malformed_request() {
        let poster = Fixed(Ok("id".into()));
        let mut left = 1;
        assert!(text(handle(&poster, &mut left, b"junk")).contains("malformed"));
        assert!(text(handle(&poster, &mut left, b"{}")).contains("budget"));
    }

    #[test]
    fn a_missing_field_is_refused() {
        let mut left = MAX_POSTS_PER_RUN;
        let out = text(handle(
            &Fixed(Ok("id".into())),
            &mut left,
            br#"{"content":"hi"}"#,
        ));
        assert!(out.contains("needs a channel_id and content"), "{out}");
    }
}
