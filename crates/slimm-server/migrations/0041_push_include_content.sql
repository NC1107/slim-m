-- SPDX-License-Identifier: AGPL-3.0-only
-- Whether this device asked for message content inside its sealed push
-- envelope. Per device, not per account: the lock screen this decides the
-- contents of belongs to one physical device, so a personal phone and a
-- shared tablet on the same account can answer differently.
--
-- Defaults to 0, so every device already registered keeps receiving exactly
-- the content-free envelope it registers for today until it re-registers
-- asking otherwise.
ALTER TABLE devices ADD COLUMN push_include_content INTEGER NOT NULL DEFAULT 0;
