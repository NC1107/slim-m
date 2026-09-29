// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! What a module run may reach through `slim.host_call`, per decision 0023.
//!
//! [`surface_for`] turns an installed module plus the invoking user into the
//! run's capability surface. Only a capability the manifest declared, the host
//! implements, and an admin approved at install is ever on it; a module with
//! none gets [`CapabilitySurface::Disabled`] and stays on the import-free ABI.
//!
//! `host_call` is a synchronous wasm import running on a blocking thread, so the
//! backends here `block_on` the async store from that thread. Each call is one
//! bounded query, and the per-run call budgets cap how many a run can make.

use std::sync::Arc;

use tokio::runtime::Handle;
use uuid::Uuid;

use super::AppState;
use super::channel_slow_mode::enforce_slow_mode;
use super::messages::validate_content;
use crate::hub::Event;
use crate::ids::{ChannelId, MessageId, UserId};
use crate::module_runtime::{
    CapabilitySurface, KvBackend, KvError, MAX_ENTRIES, MAX_TOTAL_BYTES, MessagePoster, PostRefused,
};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{InstalledModule, KvSetError, NewEmbed, NewMessage, Store};

/// The capabilities this host implements behind `slim.host_call`. A manifest
/// may declare others (it is free text); none of them can ever be approved.
pub(crate) const HOST_CAPABILITIES: [&str; 2] = ["kv.store", "message.post"];

/// Most keys a `list` returns; equal to the entry cap, so it is never truncated.
const LIST_LIMIT: i64 = MAX_ENTRIES as i64;
/// Charged against the module as a whole for every post; see [`Class::ModulePost`].
const MODULE_WIDE_POST_COST: f64 = 0.25;

/// The host capabilities `module` may use: declared in its manifest, approved
/// by an admin, and implemented here. All three, or the capability is absent.
pub(crate) fn effective_capabilities(module: &InstalledModule) -> Vec<String> {
    module
        .approved_host_capabilities
        .iter()
        .filter(|c| HOST_CAPABILITIES.contains(&c.as_str()))
        .filter(|c| module.approved_capabilities.contains(c))
        .cloned()
        .collect()
}

/// The capability surface for one run of `module`, invoked by `user_id`.
/// Must be called from inside the tokio runtime that will drive the run.
pub(crate) fn surface_for(
    state: &AppState,
    module: &InstalledModule,
    user_id: UserId,
) -> CapabilitySurface {
    let approved = effective_capabilities(module);
    if approved.is_empty() {
        return CapabilitySurface::Disabled;
    }
    let handle = Handle::current();
    let kv = Arc::new(SqliteKv {
        store: state.store.clone(),
        handle: handle.clone(),
    });
    let poster = Arc::new(ChannelPoster {
        state: state.clone(),
        handle,
        module_id: module.id.clone(),
        module_name: module.name.clone(),
        user_id,
    });
    CapabilitySurface::enabled(approved, module.id.clone(), kv).with_poster(poster)
}

struct SqliteKv {
    store: Store,
    handle: Handle,
}

impl KvBackend for SqliteKv {
    fn get(&self, module_id: &str, key: &str) -> Result<Option<String>, KvError> {
        self.handle
            .block_on(self.store.module_kv_get(module_id, key))
            .map_err(|_| KvError::Unavailable)
    }

    fn set(&self, module_id: &str, key: &str, value: &str) -> Result<(), KvError> {
        let outcome = self.handle.block_on(self.store.module_kv_set(
            module_id,
            key,
            value,
            MAX_ENTRIES as i64,
            MAX_TOTAL_BYTES as i64,
        ));
        match outcome {
            Ok(()) => Ok(()),
            Err(KvSetError::Full) => Err(KvError::Full),
            Err(KvSetError::Internal(_)) => Err(KvError::Unavailable),
        }
    }

    fn delete(&self, module_id: &str, key: &str) -> Result<(), KvError> {
        self.handle
            .block_on(self.store.module_kv_delete(module_id, key))
            .map_err(|_| KvError::Unavailable)
    }

    fn list(&self, module_id: &str) -> Result<Vec<String>, KvError> {
        self.handle
            .block_on(self.store.module_kv_keys(module_id, LIST_LIMIT))
            .map_err(|_| KvError::Unavailable)
    }
}

/// Posts as `user_id`, the user who invoked the module, and never as anyone
/// the module names.
struct ChannelPoster {
    state: AppState,
    handle: Handle,
    module_id: String,
    module_name: String,
    user_id: UserId,
}

impl MessagePoster for ChannelPoster {
    fn post(&self, channel_id: &str, content: &str) -> Result<String, PostRefused> {
        self.handle
            .block_on(self.post_async(channel_id, content))
            .map(|id| id.to_string())
    }
}

impl ChannelPoster {
    /// The same checks a first-party send makes, evaluated for the invoking
    /// user, so a module can post exactly where that user could. A missing
    /// channel and a denied one are refused identically.
    async fn post_async(&self, channel: &str, content: &str) -> Result<MessageId, PostRefused> {
        let state = &self.state;
        let channel_id = Uuid::parse_str(channel)
            .map(ChannelId)
            .map_err(|_| PostRefused("invalid channel_id"))?;
        let needed = Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES);
        match state
            .store
            .has_permission(self.user_id, channel_id, needed)
            .await
        {
            Ok(true) => {}
            Ok(false) => return Err(PostRefused("not permitted to post in that channel")),
            Err(_) => return Err(PostRefused("message.post is unavailable")),
        }
        self.charge_rate_limits()?;
        let content = validate_content(content, false)
            .map_err(|_| PostRefused("content is empty or too long"))?;
        enforce_slow_mode(state, channel_id, self.user_id)
            .await
            .map_err(|_| PostRefused("slow mode is active in that channel"))?;

        let id = MessageId::generate();
        let sent = state
            .store
            .send_message(NewMessage::plain(channel_id, self.user_id, id, content))
            .await
            .map_err(|_| PostRefused("message.post is unavailable"))?;
        let embeds = self.attribute(id).await?;

        super::message_mentions::resolve_and_store(
            state,
            channel_id,
            self.user_id,
            id,
            &sent.message.content,
        )
        .await
        .map_err(|_| PostRefused("message.post is unavailable"))?;
        super::read_sync::advance_for_author(state, self.user_id, &sent.message).await;
        state.hub.publish(Event::MessageCreated {
            message: Arc::new(sent.message.clone()),
            attachments: Arc::new(Vec::new()),
            forwarded: None,
            app_surface: None,
            code_run: None,
            poll: None,
            embeds: Arc::new(embeds),
        });
        state.push.notify_message(
            state.store.clone(),
            crate::push::SentMessage {
                channel_id,
                author_id: self.user_id,
                message_id: id,
                seq: sent.message.seq,
                content: sent.message.content.clone(),
                presence: state.hub.presence(),
            },
        );
        Ok(id)
    }

    fn charge_rate_limits(&self) -> Result<(), PostRefused> {
        let limiter = &self.state.limiter;
        let per_user = format!("mu:{}:{}", self.module_id, self.user_id);
        let module_wide = format!("m:{}", self.module_id);
        if limiter.check(Class::ModulePost, &per_user)
            && limiter.check_weighted(Class::ModulePost, &module_wide, MODULE_WIDE_POST_COST)
        {
            Ok(())
        } else {
            Err(PostRefused("message.post rate limit reached"))
        }
    }

    /// Records the module as the message's origin and stamps a footer so every
    /// client shows "via <module>" through the embed rendering it already has.
    async fn attribute(&self, id: MessageId) -> Result<Vec<crate::store::Embed>, PostRefused> {
        let store = &self.state.store;
        let footer = NewEmbed {
            footer_text: Some(format!("via {}", self.module_name)),
            ..NewEmbed::default()
        };
        let unavailable = |_| PostRefused("message.post is unavailable");
        store
            .record_module_message_origin(id, &self.module_id)
            .await
            .map_err(unavailable)?;
        store
            .set_message_embeds(id, &[footer])
            .await
            .map_err(unavailable)?;
        let stored = store
            .embeds_for_messages(&[id])
            .await
            .map_err(unavailable)?;
        Ok(stored
            .into_iter()
            .next()
            .map(|(_, embeds)| embeds)
            .unwrap_or_default())
    }
}
