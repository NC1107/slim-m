// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Dock: browsing, installing, and enabling modules from the addons
/// marketplace. See `docs/decisions/0021-modules-and-the-dock.md` for the
/// module system this is the client half of - slim ships the host and the
/// marketplace, never a module's own behavior.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// One row of the marketplace's index: enough to list a module, not enough
/// to install it. `GET /space/dock/modules`.
class DockIndexEntry {
  const DockIndexEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.summary,
  });

  /// The module's slug id, stable across versions and safe for a URL path
  /// segment.
  final String id;
  final String name;
  final String version;
  final String summary;

  factory DockIndexEntry.fromJson(Map<String, dynamic> json) => DockIndexEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        summary: json['summary'] as String,
      );
}

/// Where a module's verified artifact lives, and the hash the install call
/// checks it against before anything runs.
class DockArtifact {
  const DockArtifact({
    required this.kind,
    required this.path,
    required this.sha256,
  });

  final String kind;
  final String path;

  /// 64 lowercase hex characters.
  final String sha256;

  factory DockArtifact.fromJson(Map<String, dynamic> json) => DockArtifact(
        kind: json['kind'] as String,
        path: json['path'] as String,
        sha256: json['sha256'] as String,
      );
}

/// Resource ceilings the host enforces on a module's runtime. Any field can
/// be absent, meaning that backend applies its own default rather than the
/// manifest naming one.
class DockLimits {
  const DockLimits({this.memoryMb, this.wallMs, this.fuel});

  final int? memoryMb;
  final int? wallMs;

  /// The WASM fuel budget metering CPU use; see decision 0021's runtime
  /// section for why this replaces a wall-clock-only limit.
  final int? fuel;

  factory DockLimits.fromJson(Map<String, dynamic> json) => DockLimits(
        memoryMb: json['memory_mb'] as int?,
        wallMs: json['wall_ms'] as int?,
        fuel: json['fuel'] as int?,
      );
}

/// Which host-provided runtime a module needs, and its resource ceilings. A
/// module never ships or installs a runtime; it only names one slim already
/// offers.
class DockRuntime {
  const DockRuntime({required this.backend, required this.limits});

  final String backend;
  final DockLimits limits;

  factory DockRuntime.fromJson(Map<String, dynamic> json) => DockRuntime(
        backend: json['backend'] as String,
        limits: DockLimits.fromJson(json['limits'] as Map<String, dynamic>),
      );
}

/// One permission a module will register into the space's role editor on
/// install, namespaced by the module's own id once installed
/// (`code-exec:run`).
class DockPermission {
  const DockPermission({
    required this.key,
    required this.name,
    required this.description,
  });

  final String key;
  final String name;
  final String description;

  factory DockPermission.fromJson(Map<String, dynamic> json) => DockPermission(
        key: json['key'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
      );
}

/// One seam a module attaches to - a command, a message action, a scheduled
/// job. The first release defines `command` only.
class DockExtensionPoint {
  const DockExtensionPoint({
    required this.kind,
    required this.name,
    this.description,
  });

  final String kind;
  final String name;
  final String? description;

  factory DockExtensionPoint.fromJson(Map<String, dynamic> json) =>
      DockExtensionPoint(
        kind: json['kind'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
      );
}

/// A module's full manifest, as `GET /space/dock/modules/{id}` returns it: the
/// permissions it will add and the capabilities it asks for, shown before an
/// admin ever installs it.
class DockManifest {
  const DockManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.summary,
    this.author,
    required this.artifact,
    required this.runtime,
    required this.permissions,
    required this.capabilities,
    required this.extensionPoints,
  });

  final String id;
  final String name;
  final String version;
  final String summary;
  final String? author;
  final DockArtifact artifact;
  final DockRuntime runtime;

  /// Registered into the space's permission registry on install; see
  /// `docs/decisions/0021-modules-and-the-dock.md`'s "Dynamic permissions".
  final List<DockPermission> permissions;

  /// What the module asks the host for. The admin approves this set at
  /// install; the host refuses any host call outside it.
  final List<String> capabilities;
  final List<DockExtensionPoint> extensionPoints;

  factory DockManifest.fromJson(Map<String, dynamic> json) => DockManifest(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        summary: json['summary'] as String,
        author: json['author'] as String?,
        artifact:
            DockArtifact.fromJson(json['artifact'] as Map<String, dynamic>),
        runtime: DockRuntime.fromJson(json['runtime'] as Map<String, dynamic>),
        permissions: (json['permissions'] as List<dynamic>)
            .map((p) => DockPermission.fromJson(p as Map<String, dynamic>))
            .toList(growable: false),
        capabilities: (json['capabilities'] as List<dynamic>)
            .map((c) => c as String)
            .toList(growable: false),
        extensionPoints: (json['extension_points'] as List<dynamic>)
            .map((e) => DockExtensionPoint.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One module this space has installed, from the Dock's lifecycle calls and
/// `GET /space/dock/installed`.
class InstalledDockModule {
  const InstalledDockModule({
    required this.id,
    required this.name,
    required this.version,
    required this.artifactSha256,
    required this.approvedCapabilities,
    required this.enabled,
    required this.installedAt,
  });

  final String id;
  final String name;
  final String version;
  final String artifactSha256;
  final List<String> approvedCapabilities;

  /// Off by default: installing never runs a module, a separate enable call
  /// does.
  final bool enabled;

  /// Unix milliseconds.
  final int installedAt;

  factory InstalledDockModule.fromJson(Map<String, dynamic> json) =>
      InstalledDockModule(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        artifactSha256: json['artifact_sha256'] as String,
        approvedCapabilities: (json['approved_capabilities'] as List<dynamic>)
            .map((c) => c as String)
            .toList(growable: false),
        enabled: json['enabled'] as bool,
        installedAt: json['installed_at'] as int,
      );
}
