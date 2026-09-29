# 0046 - More than one module source

Status: accepted
Extends: 0021 (modules and the Dock), 0023 (module capabilities)

## Context

The Dock read one registry, `Config::addons_repo`.
Pointing a deployment at a different repo replaced the curated catalog instead of adding to it.
The owner asked for a `+` so a community module can sit beside the official ones, with the official repo keeping the documentation and review pipeline for known-safe modules.

## Decision

An admin (MANAGE_SERVER, the Dock's existing gate) can add and remove community sources.
Every route stays behind that one permission, and nothing here widens what a non-admin can reach.

### A source is a repo slug, not a URL

A source is a GitHub `owner/repo`, read from the same fixed `raw.githubusercontent.com` host as the official one.
The slug is validated against GitHub's own character rules, so it cannot carry a scheme, host, port, query, fragment or `..` segment.
The host allowlist in `ssrf.rs` and `fetch.rs` is unchanged, so there is no new SSRF surface and no private-address case to gate behind an operator flag.
A LAN registry is out of scope on purpose: it needs the host to be configurable, which is exactly what the fixed host prevents.
If a self-hosted registry is wanted later, it should be its own decision, with its own operator flag.

### Same bar as the official source

A community source's index, manifests and artifacts go through the same `parse_index`, `parse_manifest` and sha256 check as the official one's.
The official index pins nothing beyond that (each manifest pins its artifact's sha256), so there is no stricter check to match and no "unverified" tier.
Capability approval per module (0023) is unchanged: the admin still approves each host capability at install.
The Dock labels a community module with its `owner/repo` so the admin knows where it came from before installing it.

### Module ids do not collide: refuse, do not namespace

The module id is the installed row's primary key, the prefix of its permission keys, and the `moduleId` segment of every command route and stored app surface.
Namespacing would rewrite all of those, and every existing module and bot integration would need migrating.
So an id has exactly one owner:

- the official source always wins: a community source cannot install an id the official index publishes (409);
- an id installed from one source stays with it until uninstalled: installing it from another source is refused (409);
- a listing marks such entries `shadowed`, so the client can disable them and say why.

If the official index cannot be read when a community install needs the check, the install fails rather than skipping it.
Between two community sources, whichever installed the id first keeps it.

### Removing a source does not uninstall anything

Modules already installed from a removed source stay installed and enabled, and keep their `source_repo` label.
Uninstalling a running module is destructive (its data and grants cascade away), and losing a listing is not a reason to do that.
What they lose is updates: installing from that repo needs the source, so re-adding the same repo restores them.
The official source cannot be removed.

## Consequences

- `dock_sources` table and `installed_modules.source_repo` (migration 0089); null means official.
- `GET/POST /space/dock/sources`, `DELETE /space/dock/sources/{sourceId}`, and a `source` query parameter on the module list, get and install routes.
- The client lists each source as its own section, so one broken source shows its own error and the others still load.
- At most 8 community sources, to bound the fan-out of a Dock load.
