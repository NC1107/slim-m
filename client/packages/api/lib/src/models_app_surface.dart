// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The app a message launches, per `docs/decisions/0021-modules-and-the-dock.md`'s
/// module-agnostic principle: this only says which `(module_id, command)` the
/// message launched, never what it does. The surface's live, shared state is
/// the module's own output, carried as this message's code run at block 0 (see
/// [CodeRun]), so an app surface reuses the shared code-run machinery whole.
///
/// Split out of models.dart purely to stay under this repo's line budget.
library;

/// The app a message launches, attached to a [Message] as `appSurface`. Null
/// on an ordinary message; fixed once the message exists, like a poll.
class AppSurface {
  const AppSurface({required this.moduleId, required this.command});

  final String moduleId;
  final String command;

  factory AppSurface.fromJson(Map<String, dynamic> json) => AppSurface(
        moduleId: json['module_id'] as String,
        command: json['command'] as String,
      );
}
