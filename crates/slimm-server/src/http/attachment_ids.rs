// SPDX-License-Identifier: AGPL-3.0-only
//! Parsing and bounding a send's attachment id list, split out of
//! `messages.rs` so it has a home to be unit-tested in and the handler file
//! stays under its line budget. A pure function of its argument.

use super::error::ApiError;
use crate::media;
use crate::store::MAX_ATTACHMENTS_PER_MESSAGE;

/// Parses and bounds a send's attachment id list. Each id must be a
/// well-formed 32-byte sha256 in hex. Whether the sender uploaded it, or can
/// currently view a channel that already has it, is checked by
/// [`crate::store::Store::send_message`], and answers exactly as a
/// never-uploaded id does.
pub(super) fn parse_attachment_ids(raw: &[String]) -> Result<Vec<Vec<u8>>, ApiError> {
    if raw.len() > MAX_ATTACHMENTS_PER_MESSAGE {
        return Err(ApiError::BadRequest("too many attachments"));
    }
    let ids: Vec<Vec<u8>> = raw
        .iter()
        .map(|s| {
            media::from_hex(s)
                .filter(|bytes| bytes.len() == 32)
                .ok_or(ApiError::BadRequest("invalid attachment id"))
        })
        .collect::<Result<_, _>>()?;
    // Refused here rather than as the 500 the link table's primary key turns a repeat into.
    let mut seen = std::collections::HashSet::new();
    if !ids.iter().all(|id| seen.insert(id.clone())) {
        return Err(ApiError::BadRequest("duplicate attachment id"));
    }
    Ok(ids)
}

#[cfg(test)]
mod tests {
    use super::parse_attachment_ids;
    use crate::store::MAX_ATTACHMENTS_PER_MESSAGE;

    #[test]
    fn a_well_formed_list_parses_and_an_empty_one_is_fine() {
        let ids = vec![format!("{:064x}", 1), format!("{:064x}", 2)];
        let Ok(parsed) = parse_attachment_ids(&ids) else {
            panic!("well-formed ids parse");
        };
        assert_eq!(parsed.len(), 2);
        assert!(matches!(parse_attachment_ids(&[]), Ok(v) if v.is_empty()));
    }

    #[test]
    fn more_than_the_cap_is_refused() {
        let ids: Vec<String> = (0..=MAX_ATTACHMENTS_PER_MESSAGE as u64)
            .map(|n| format!("{n:064x}"))
            .collect();
        assert!(parse_attachment_ids(&ids).is_err());
    }

    /// An id must be hex and exactly 32 bytes: a non-hex string and a
    /// well-formed but too-short one are both refused, so a malformed id can
    /// never reach the store as a lookup that silently matches nothing.
    #[test]
    fn a_malformed_or_wrong_length_id_is_refused() {
        assert!(parse_attachment_ids(&["not hex".to_owned()]).is_err());
        assert!(parse_attachment_ids(&["abcd".to_owned()]).is_err());
    }

    #[test]
    fn a_duplicate_id_is_refused() {
        let dup = format!("{:064x}", 7);
        assert!(parse_attachment_ids(&[dup.clone(), dup]).is_err());
    }
}
