// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Embeds: the colour-to-accent mapping and the wire DTO, read side only.
//!
//! The caps that bound an embed at write time (Discord's own published
//! limits, so a caller's tool already written against Discord's contract is
//! never bitten by a slim-m-specific ceiling) land with the first caller
//! that can actually create one - the webhook delivery route and the
//! ordinary send route, sharing one implementation so the two cannot drift
//! apart. Nothing here yet writes a [`StoreEmbed`]; this module only turns
//! one already in the store into what a read path answers with. See
//! `docs/decisions/0030-incoming-webhooks.md`'s "Where embeds live".
//!
//! One thing Discord's embed has that this one deliberately does not:
//! `author.icon_url` and `footer.icon_url`. Both are a small avatar-shaped
//! image next to a name, which is exactly the identity-spoofing objection
//! `docs/decisions/0030-incoming-webhooks.md` already gives for dropping
//! `avatar_url` outright - so they get the same answer, rather than
//! reopening it for two more image fields.

use serde::Serialize;

use crate::store::Embed as StoreEmbed;

/// A caller-supplied colour, reduced to one of a small closed set of
/// pre-tuned swatches - never rendered as a raw hex fill.
///
/// slim-m's design system keeps its one accent hue closed to seven unrelated
/// chrome roles (`docs/decisions/0004-visual-identity-review.md`), so an
/// embed's colour is not that accent and does not add an eighth role to it.
/// It is a second, separate closed palette that exists only to let a caller
/// tell one embed's *kind* from another at a glance (an alert firing versus
/// one resolved, a build failure versus a deploy) - the same closed-role
/// treatment the canvas's own `AppCanvasColors` already gives note/shape
/// colour, for the same reason. The client paints it only as a thin border
/// stripe and a soft tint, never as text, so no caller input can ever land
/// on a contrast failure: the swatches are pre-tuned per theme and the text
/// above them always uses the ordinary neutral tokens.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EmbedAccent {
    Red,
    Orange,
    Yellow,
    Green,
    Blue,
    Purple,
}

/// Buckets a caller's raw 24-bit RGB integer into one of six hue ranges, or
/// `None` when the colour is absent, out of range, or too close to grey,
/// black or white to read as a colour at all - a webhook that sends `0`
/// (black) or omits `color` gets a plain, unaccented card rather than a
/// meaningless "black" stripe.
pub fn accent_for(color: i64) -> Option<EmbedAccent> {
    if !(0..=0xFF_FFFF).contains(&color) {
        return None;
    }
    let r = ((color >> 16) & 0xFF) as f64 / 255.0;
    let g = ((color >> 8) & 0xFF) as f64 / 255.0;
    let b = (color & 0xFF) as f64 / 255.0;
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;
    let lightness = (max + min) / 2.0;
    if delta < 0.04 || !(0.06..0.94).contains(&lightness) {
        return None;
    }
    let saturation = delta / (1.0 - (2.0 * lightness - 1.0).abs());
    if saturation < 0.15 {
        return None;
    }
    let hue = if max == r {
        60.0 * (((g - b) / delta).rem_euclid(6.0))
    } else if max == g {
        60.0 * (((b - r) / delta) + 2.0)
    } else {
        60.0 * (((r - g) / delta) + 4.0)
    };
    // Six named buckets over the full 0-360 hue circle. Uneven on purpose:
    // green and blue each cover a perceptually wide band, red a narrow one
    // either side of zero.
    let hue = hue.rem_euclid(360.0);
    Some(match hue {
        h if !(15.0..345.0).contains(&h) => EmbedAccent::Red,
        h if h < 45.0 => EmbedAccent::Orange,
        h if h < 80.0 => EmbedAccent::Yellow,
        h if h < 170.0 => EmbedAccent::Green,
        h if h < 255.0 => EmbedAccent::Blue,
        _ => EmbedAccent::Purple,
    })
}

/// One field on an embed, exactly as it renders.
#[derive(Serialize)]
pub(crate) struct EmbedFieldDto {
    pub(crate) name: String,
    pub(crate) value: String,
    pub(crate) inline: bool,
}

/// One embed as a message carries it. Images are never raw URLs - see this
/// module's own doc and `docs/decisions/0019-link-unfurling-and-ssrf-defense.md` -
/// they are redeemable tokens through the same `GET
/// /link-preview/image/{token}` an ordinary pasted link's preview already
/// uses, minted by `LinkPreviews::embed_image_token`. Absent whenever the
/// caller sent no image, the URL failed the guard, or this deployment has
/// not opted into outbound image fetching at all (`SLIMM_LINK_PREVIEWS`) -
/// every one of those degrades the same way, to no image, never an error.
#[derive(Serialize)]
pub(crate) struct EmbedDto {
    pub(crate) title: Option<String>,
    pub(crate) description: Option<String>,
    pub(crate) url: Option<String>,
    pub(crate) accent: Option<EmbedAccent>,
    pub(crate) author_name: Option<String>,
    pub(crate) author_url: Option<String>,
    #[serde(default)]
    pub(crate) fields: Vec<EmbedFieldDto>,
    pub(crate) footer_text: Option<String>,
    pub(crate) timestamp: Option<i64>,
    pub(crate) image_token: Option<String>,
    pub(crate) thumbnail_token: Option<String>,
}

/// Builds the wire DTO for one stored embed. Image/thumbnail tokens are
/// resolved by the caller (`http::message_enrich`) - this function only
/// assembles what it is handed, since minting a token is an
/// [`crate::http::link_preview::LinkPreviews`] call this module has no
/// handle to make on its own.
pub(crate) fn to_dto(
    embed: StoreEmbed,
    image_token: Option<String>,
    thumbnail_token: Option<String>,
) -> EmbedDto {
    EmbedDto {
        title: embed.title,
        description: embed.description,
        url: embed.url,
        accent: embed.color.and_then(accent_for),
        author_name: embed.author_name,
        author_url: embed.author_url,
        fields: embed
            .fields
            .into_iter()
            .map(|f| EmbedFieldDto {
                name: f.name,
                value: f.value,
                inline: f.inline,
            })
            .collect(),
        footer_text: embed.footer_text,
        timestamp: embed.timestamp,
        image_token,
        thumbnail_token,
    }
}

/// Every URL an embed carries that must be resolved to an image token before
/// [`to_dto`] can run - `(image_url, thumbnail_url)`, either half absent
/// when that field is absent.
pub(crate) fn image_urls(embed: &StoreEmbed) -> (Option<&str>, Option<&str>) {
    (embed.image_url.as_deref(), embed.thumbnail_url.as_deref())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pure_red_buckets_to_red() {
        assert_eq!(accent_for(0xE0_3B3B), Some(EmbedAccent::Red));
    }

    #[test]
    fn a_pure_green_buckets_to_green() {
        assert_eq!(accent_for(0x2E_A043), Some(EmbedAccent::Green));
    }

    #[test]
    fn a_pure_blue_buckets_to_blue() {
        assert_eq!(accent_for(0x1B_6F91), Some(EmbedAccent::Blue));
    }

    #[test]
    fn a_purple_buckets_to_purple() {
        assert_eq!(accent_for(0x8A_3FFC), Some(EmbedAccent::Purple));
    }

    #[test]
    fn black_has_no_accent() {
        assert_eq!(accent_for(0x00_0000), None);
    }

    #[test]
    fn white_has_no_accent() {
        assert_eq!(accent_for(0xFF_FFFF), None);
    }

    #[test]
    fn a_near_grey_has_no_accent() {
        assert_eq!(accent_for(0x80_8080), None);
    }

    #[test]
    fn an_out_of_range_value_has_no_accent() {
        assert_eq!(accent_for(-1), None);
        assert_eq!(accent_for(0x0100_0000), None);
    }
}
