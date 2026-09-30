// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! One enabled module per slash keyword, so a `/name` can never run a module the admin did not mean.

use crate::http::AppState;
use crate::http::error::ApiError;
use crate::store::ModuleExtensionPoint;

/// The keywords a module's `slash-command` extension points claim.
pub(super) fn slash_keywords(points: &[ModuleExtensionPoint]) -> impl Iterator<Item = &str> {
    points
        .iter()
        .filter(|p| p.kind == "slash-command")
        .map(|p| p.name.as_str())
}

/// Refuses when another enabled module already owns one of `keywords`, because
/// the client would otherwise run whichever was listed first.
pub(super) async fn ensure_slash_keywords_free<'a>(
    state: &AppState,
    module_id: &str,
    keywords: impl Iterator<Item = &'a str>,
) -> Result<(), ApiError> {
    let wanted: Vec<String> = keywords.map(str::to_lowercase).collect();
    if wanted.is_empty() {
        return Ok(());
    }
    for other in state.store.list_installed_modules().await? {
        if other.id == module_id || !other.enabled {
            continue;
        }
        if let Some(clash) = slash_keywords(&other.extension_points)
            .find(|name| wanted.contains(&name.to_lowercase()))
        {
            return Err(ApiError::ConflictDetail(format!(
                "the slash command /{clash} is already provided by the enabled module {}; disable it first",
                other.id
            )));
        }
    }
    Ok(())
}
