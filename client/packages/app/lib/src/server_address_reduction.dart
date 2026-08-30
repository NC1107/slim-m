// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Reducing a typed server address to the part that is safe to keep.
library;

/// Strips everything from [address] but the scheme, host and port.
///
/// Userinfo must never survive: dart:io turns it into a Basic auth header on
/// every request the stored base URL makes afterward, so a pasted
/// `https://user:pass@host` would silently start authenticating every call
/// with those credentials. A path is dropped too, and deliberately not
/// preserved: the API client's transport replaces the whole path with each
/// endpoint's own literal one on every request, so a base path saved here
/// would be discarded downstream regardless - a server mounted under a
/// subpath is not a deployment shape this client supports today.
Uri reduceServerAddress(Uri address) => Uri(
  scheme: address.scheme,
  host: address.host,
  port: address.hasPort ? address.port : null,
);
