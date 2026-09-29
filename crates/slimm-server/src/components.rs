// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Buttons a bot attaches to its own message, and the caps that keep them
//! bounded. See docs/decisions/0038-bot-message-buttons.md.
//!
//! One shape serves the wire and storage: a bot sends it, the server checks it
//! once here, stores it as JSON and reads it back unchanged.

use serde::{Deserialize, Serialize};

/// Rows a message may carry. Discord's own ceiling, so its bots port cleanly.
pub const MAX_ROWS: usize = 5;
pub const MAX_BUTTONS_PER_ROW: usize = 5;
pub const MAX_LABEL_CHARS: usize = 80;
pub const MAX_CUSTOM_ID_CHARS: usize = 100;
pub const MAX_URL_CHARS: usize = 512;

/// How long a click can still be answered. Also the lifetime of its row.
pub const INTERACTION_WINDOW_MS: i64 = 15 * 60 * 1000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ButtonStyle {
    Primary,
    Secondary,
    Danger,
    Link,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Button {
    pub label: String,
    pub style: ButtonStyle,
    /// Present on every button except a link, which never reaches the bot.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom_id: Option<String>,
    /// Present only on a link button.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(default)]
    pub disabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ComponentRow {
    pub buttons: Vec<Button>,
}

/// Checks a bot's rows against the caps and returns them trimmed. The error is
/// the wire-facing text.
pub fn validate(mut rows: Vec<ComponentRow>) -> Result<Vec<ComponentRow>, &'static str> {
    if rows.len() > MAX_ROWS {
        return Err("too many component rows");
    }
    let mut seen = std::collections::HashSet::new();
    for row in &mut rows {
        if row.buttons.is_empty() {
            return Err("a component row must hold at least one button");
        }
        if row.buttons.len() > MAX_BUTTONS_PER_ROW {
            return Err("too many buttons in a row");
        }
        for button in &mut row.buttons {
            validate_button(button)?;
            if let Some(id) = &button.custom_id
                && !seen.insert(id.clone())
            {
                return Err("custom_id must be unique within a message");
            }
        }
    }
    Ok(rows)
}

fn validate_button(button: &mut Button) -> Result<(), &'static str> {
    button.label = button.label.trim().to_owned();
    if button.label.is_empty() {
        return Err("a button needs a label");
    }
    if button.label.chars().count() > MAX_LABEL_CHARS {
        return Err("button label is too long");
    }
    if button.style == ButtonStyle::Link {
        return validate_link(button);
    }
    if button.url.is_some() {
        return Err("only a link button takes a url");
    }
    let id = button
        .custom_id
        .as_deref()
        .ok_or("a button needs a custom_id")?;
    if id.is_empty() || id.chars().count() > MAX_CUSTOM_ID_CHARS {
        return Err("custom_id must be 1 to 100 characters");
    }
    Ok(())
}

fn validate_link(button: &mut Button) -> Result<(), &'static str> {
    if button.custom_id.is_some() {
        return Err("a link button takes a url, not a custom_id");
    }
    let url = button.url.as_deref().ok_or("a link button needs a url")?;
    if url.chars().count() > MAX_URL_CHARS {
        return Err("button url is too long");
    }
    let lower = url.to_ascii_lowercase();
    if !(lower.starts_with("https://") || lower.starts_with("http://")) {
        return Err("a button url must be http or https");
    }
    Ok(())
}

/// The enabled, non-link button carrying `custom_id`, if any.
pub fn clickable<'a>(rows: &'a [ComponentRow], custom_id: &str) -> Option<&'a Button> {
    rows.iter()
        .flat_map(|row| &row.buttons)
        .find(|b| b.custom_id.as_deref() == Some(custom_id) && !b.disabled)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn button(id: &str) -> Button {
        Button {
            label: "Hit".into(),
            style: ButtonStyle::Primary,
            custom_id: Some(id.into()),
            url: None,
            disabled: false,
        }
    }

    fn row(buttons: Vec<Button>) -> ComponentRow {
        ComponentRow { buttons }
    }

    #[test]
    fn a_full_five_by_five_grid_passes() {
        let rows = (0..5)
            .map(|r| row((0..5).map(|c| button(&format!("b{r}{c}"))).collect()))
            .collect();
        assert!(validate(rows).is_ok());
    }

    #[test]
    fn a_sixth_row_or_button_is_refused() {
        let rows = (0..6)
            .map(|r| row(vec![button(&format!("r{r}"))]))
            .collect();
        assert!(validate(rows).is_err());
        let wide = vec![row((0..6).map(|c| button(&format!("c{c}"))).collect())];
        assert!(validate(wide).is_err());
    }

    #[test]
    fn duplicate_custom_ids_are_refused() {
        assert!(validate(vec![row(vec![button("a"), button("a")])]).is_err());
    }

    #[test]
    fn a_link_needs_an_http_url_and_no_custom_id() {
        let mut link = button("x");
        link.style = ButtonStyle::Link;
        assert!(validate(vec![row(vec![link.clone()])]).is_err());
        link.custom_id = None;
        link.url = Some("javascript:alert(1)".into());
        assert!(validate(vec![row(vec![link.clone()])]).is_err());
        link.url = Some("https://example.com".into());
        assert!(validate(vec![row(vec![link])]).is_ok());
    }

    #[test]
    fn a_blank_or_oversize_label_is_refused() {
        let mut b = button("a");
        b.label = "   ".into();
        assert!(validate(vec![row(vec![b.clone()])]).is_err());
        b.label = "x".repeat(MAX_LABEL_CHARS + 1);
        assert!(validate(vec![row(vec![b])]).is_err());
    }

    #[test]
    fn a_disabled_button_is_not_clickable() {
        let mut b = button("a");
        b.disabled = true;
        assert!(clickable(&[row(vec![b])], "a").is_none());
    }
}
