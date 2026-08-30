// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one server this build knows about without being told.
///
/// Compiled in rather than typed, so joining it can skip both the address
/// prompt and the manual identity check that exist for a server only its own
/// host can vouch for: there is no admin to read a fingerprint to, and the
/// binary and the address are already the same trust decision.
library;

/// The official instance. Someone with no invite and no server of their own
/// still needs somewhere to land.
const officialServer = 'https://slim.npc-server.top';

/// Whether [address] is the compiled-in official server, compared by origin
/// so a trailing slash or an explicit default port cannot dodge the check.
bool isOfficialServer(Uri address) =>
    address.origin == Uri.parse(officialServer).origin;
