// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// The Dock: the module marketplace's browse, install and lifecycle calls.
/// Every route here requires MANAGE_SERVER. See
/// `docs/decisions/0021-modules-and-the-dock.md` - this is Phase 1 (browse)
/// and Phase 2 (install/enable/uninstall, dynamic permissions) only; no
/// module code ever runs from anything in this file.
extension SlimmApiDock on SlimmApi {
  /// Browses the marketplace's index. Nothing is installed by this call.
  Future<List<DockIndexEntry>> listDockModules() async {
    final json = await _send('GET', '/space/dock/modules');
    return (json as List<dynamic>)
        .map((m) => DockIndexEntry.fromJson(m as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Reads one module's full manifest, including every permission it will
  /// register and every capability it asks for, before installing it.
  Future<DockManifest> getDockModule(String moduleId) async {
    final json = await _send('GET', '/space/dock/modules/$moduleId');
    return DockManifest.fromJson(json as Map<String, dynamic>);
  }

  /// Installs a module at [version], the one reviewed in the Dock. Refused
  /// with 409 if the registry's current manifest no longer matches it.
  /// Installed off (disabled); a separate [enableDockModule] call turns it
  /// on.
  Future<InstalledDockModule> installDockModule({
    required String moduleId,
    required String version,
  }) async {
    final json = await _send(
      'POST',
      '/space/dock/modules/$moduleId/install',
      body: {'version': version},
    );
    return InstalledDockModule.fromJson(json as Map<String, dynamic>);
  }

  /// Uninstalls a module: removes the install, its registered permissions,
  /// and every role grant of them.
  Future<void> uninstallDockModule(String moduleId) => _send(
        'DELETE',
        '/space/dock/modules/$moduleId/install',
        expectNoContent: true,
      );

  /// Enables an installed module.
  Future<InstalledDockModule> enableDockModule(String moduleId) async {
    final json = await _send('POST', '/space/dock/modules/$moduleId/enable');
    return InstalledDockModule.fromJson(json as Map<String, dynamic>);
  }

  /// Disables an installed module without losing its config.
  Future<InstalledDockModule> disableDockModule(String moduleId) async {
    final json = await _send('POST', '/space/dock/modules/$moduleId/disable');
    return InstalledDockModule.fromJson(json as Map<String, dynamic>);
  }

  /// Every module this space currently has installed.
  Future<List<InstalledDockModule>> listInstalledDockModules() async {
    final json = await _send('GET', '/space/dock/installed');
    return (json as List<dynamic>)
        .map((m) => InstalledDockModule.fromJson(m as Map<String, dynamic>))
        .toList(growable: false);
  }
}
