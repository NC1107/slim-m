// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Runs an installed module's command, per docs/decisions/0021-modules-and-
//! the-dock.md's Phase 3. This is the one route that ever executes a
//! module: everything it decides before handing off to
//! `crate::module_runtime::ModuleHost` is gating, never behavior - slim has
//! no notion of what any command actually does.
//!
//! The wire shapes here (`{ "input": ... }` in, `{ "ok", "output" / "error" }`
//! out) are exactly the module ABI's own request/response JSON (see
//! `module_runtime`'s doc), plus the `command` name this route already knows
//! from the path. A run that fails for a host reason - a resource limit, a
//! malformed module response, a missing artifact - still answers 200 with
//! `{ "ok": false, "error": ... }`: only the gating checks below (is it
//! installed, enabled, does the caller hold its permission) use a distinct
//! status code, because those are refusals to even attempt the call rather
//! than an outcome of attempting it.
//!
//! `GET /modules/code-block-runners` lives here too: the general mechanism a
//! client uses to learn whether it may offer "Run" on a fenced code block,
//! per docs/decisions/0021-modules-and-the-dock.md's module-agnostic
//! principle. slim has no notion of "code execution" anywhere in this file -
//! it only surfaces, per caller, which installed and enabled module declared
//! a `code-block-runner` extension point the caller holds the permission
//! for. A deployment with no such module installed answers an empty list.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::routing::{get, post};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::dock::validate_module_id;
use super::error::ApiError;
use super::extract::{AUTHED_READ, AuthedLimited, Json, WRITE};
use crate::module_runtime::{ModuleHost, RunError, RunLimits};
use crate::store::InstalledModule;

/// A command name is compared verbatim against a module's own persisted
/// extension points, never used as a path or SQL fragment, so this bounds
/// only how much of a caller-supplied string this route will look at before
/// giving up on a match.
const MAX_COMMAND_LEN: usize = 64;
/// A command's `input` is a whole snippet, not a short field, so this is
/// sized well above the other small write bodies in this crate - the real
/// ceiling on what a module can do with it is its own `runtime.limits`, not
/// this transport cap.
const BODY_LIMIT: usize = 256 * 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/modules/{moduleId}/commands/{command}", post(run_command))
        .route("/modules/code-block-runners", get(list_code_block_runners))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Deserialize)]
struct RunCommandRequest {
    input: String,
}

/// The module ABI's own response shape, echoed straight through: see
/// `module_runtime`'s doc for why this route trusts it no further than
/// requiring it to actually be this shape.
#[derive(Serialize)]
struct RunCommandResponse {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    output: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl RunCommandResponse {
    fn failure(error: impl Into<String>) -> Self {
        Self {
            ok: false,
            output: None,
            error: Some(error.into()),
        }
    }
}

#[derive(Serialize)]
struct ModuleWireRequest<'a> {
    command: &'a str,
    input: &'a str,
}

#[derive(Deserialize)]
struct ModuleWireResponse {
    ok: bool,
    #[serde(default)]
    output: Option<String>,
    #[serde(default)]
    error: Option<String>,
}

fn validate_command_name(name: &str) -> Result<(), ApiError> {
    if name.is_empty() || name.len() > MAX_COMMAND_LEN {
        return Err(ApiError::BadRequest("invalid command name"));
    }
    Ok(())
}

/// The command's required permission key, from the module's own persisted
/// extension points. `None` when no `command` extension point named
/// `command` exists at all - the caller gets 404, the same as an unknown
/// module.
fn required_permission<'a>(module: &'a InstalledModule, command: &str) -> Option<&'a str> {
    module
        .extension_points
        .iter()
        .find(|e| e.kind == "command" && e.name == command)
        .and_then(|e| e.permission.as_deref())
}

async fn run_command(
    AuthedLimited(ctx): AuthedLimited<WRITE>,
    State(state): State<AppState>,
    Path((module_id, command)): Path<(String, String)>,
    Json(req): Json<RunCommandRequest>,
) -> Result<Json<RunCommandResponse>, ApiError> {
    validate_module_id(&module_id)?;
    validate_command_name(&command)?;

    let module = state
        .store
        .installed_module(&module_id)
        .await?
        .ok_or(ApiError::NotFound("module not installed"))?;
    if !module.enabled {
        return Err(ApiError::Conflict("module is not enabled"));
    }
    let permission = required_permission(&module, &command)
        .ok_or(ApiError::NotFound("module declares no such command"))?;
    if !state
        .store
        .user_has_module_permission(ctx.user_id, &module_id, permission)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let Some((sha256, wasm)) = state.store.module_artifact(&module_id).await? else {
        return Err(ApiError::Conflict(
            "module has no stored artifact; reinstall it from the Dock",
        ));
    };
    let limits = RunLimits::from(&module.runtime_limits);
    let request_json = serde_json::to_vec(&ModuleWireRequest {
        command: &command,
        input: &req.input,
    })
    .map_err(|_| ApiError::Internal)?;

    let response = match ModuleHost::run(wasm, sha256, limits, request_json).await {
        Ok(bytes) => match serde_json::from_slice::<ModuleWireResponse>(&bytes) {
            Ok(wire) if wire.ok && wire.output.is_some() => RunCommandResponse {
                ok: true,
                output: wire.output,
                error: None,
            },
            Ok(wire) if !wire.ok && wire.error.is_some() => RunCommandResponse {
                ok: false,
                output: None,
                error: wire.error,
            },
            _ => RunCommandResponse::failure("module returned a malformed response"),
        },
        Err(err) => RunCommandResponse::failure(describe(&err)),
    };
    Ok(Json(response))
}

/// A message safe to hand back to the caller: every [`RunError`] variant is
/// already a clean, non-sensitive description (see its own `Display`), never
/// a stack trace or an internal type path.
fn describe(err: &RunError) -> String {
    err.to_string()
}

/// One `(module_id, command)` pair a client may `POST` to
/// `/modules/{moduleId}/commands/{command}` to run a fenced code block.
#[derive(Serialize)]
struct CodeBlockRunnerDto {
    module_id: String,
    command: String,
}

/// Every `code-block-runner` extension point the caller may currently reach:
/// installed, enabled, and the caller holds the permission it declared. This
/// is the whole of how a client learns whether to offer "Run" on a fenced
/// code block - never a hardcoded module id, per docs/decisions/0021's
/// module-agnostic principle. Possibly empty, which means no Run affordance
/// anywhere in the client.
async fn list_code_block_runners(
    AuthedLimited(ctx): AuthedLimited<AUTHED_READ>,
    State(state): State<AppState>,
) -> Result<Json<Vec<CodeBlockRunnerDto>>, ApiError> {
    let modules = state.store.list_installed_modules().await?;
    let mut runners = Vec::new();
    for module in modules {
        if !module.enabled {
            continue;
        }
        for ep in &module.extension_points {
            if ep.kind != "code-block-runner" {
                continue;
            }
            let (Some(command), Some(permission)) = (&ep.command, &ep.permission) else {
                continue;
            };
            if state
                .store
                .user_has_module_permission(ctx.user_id, &module.id, permission)
                .await?
            {
                runners.push(CodeBlockRunnerDto {
                    module_id: module.id.clone(),
                    command: command.clone(),
                });
            }
        }
    }
    Ok(Json(runners))
}
