// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The ed25519 public keys a release manifest may be signed by.
library;

/// Standard base64 of the 32 raw key bytes. A rotation ships a release that
/// carries both keys, so this is a list from the start (decision 0041).
const trustedUpdateKeys = <String>[
  'woa3DXtmSfxh5Bo73XXspaVARTH9UzYl5JcuyRCfDp0=',
];
