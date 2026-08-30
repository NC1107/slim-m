<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->

# Licensing

slim-m is under [PolyForm Noncommercial 1.0.0](LICENSE), one license for the whole repository.
Server, client, schema, scripts, deploy and everything else are the same, so there is no per-path table to keep in sync anymore.

Every source file carries an `SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0` header, and CI checks the headers are present.
The canonical text lives in `LICENSES/LicenseRef-PolyForm-Noncommercial-1.0.0.txt` (REUSE style) and is the same text as `LICENSE`.

## What that means

Noncommercial use is free: personal, hobby, educational, research, nonprofit, and all that.
You can run it, fork it, change it and redistribute it.
You just can't sell it, host it as a paid service, or use it inside a commercial entity without a separate license.
If you want to use it commercially, open an issue and ask.

## Why it changed

It used to be split, AGPL-3.0-only for the server and Apache-2.0 for the client, on the theory that the network copyleft closed the SaaS rehosting hole.
It doesn't really. AGPL still permits commercial use and paid hosting, it only asks that the source goes with it, so someone could run a paid slim-m and comply by publishing their changes.
The client was worse for this, Apache-2.0 is permissive, so anyone could take it, close it and ship it commercially.
The goal was always that nobody else productizes this, and PolyForm says that directly instead of trying to get there through disclosure rules.

## Dependencies

`deny.toml` still gates dependency licenses to permissive ones, and matters more now rather than less.
slim-m is not open source, so it cannot take on a copyleft dependency's source-disclosure obligation.
`dbus` and `nm` stay named exceptions for MPL-2.0, which is per-file copyleft on those files and reaches neither half of slim-m.
