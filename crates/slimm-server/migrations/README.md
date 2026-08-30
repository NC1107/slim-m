<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->

# Do not edit an applied migration, including its header comment

Every `.sql` file here still carries `SPDX-License-Identifier: AGPL-3.0-only`.
That is deliberate, and it is the one place in this repository the PolyForm
relicense was correctly **not** applied.

sqlx validates each applied migration with a sha384 over the file's **bytes**
and refuses to start the process when one differs. The header comment is part
of those bytes. Rewriting it changes the checksum of a migration that
deployed databases have already recorded, and every one of them then
bootloops on:

```
Error: running database migrations
Caused by:
    migration 1 was previously applied but has been modified
```

That is not hypothetical. It happened on 2026-08-30: the relicense swept the
header across all 54 migration files then on disk, the image built and
deployed on its own, and the live server bootlooped until the headers were
restored byte-for-byte.

The project's license is PolyForm Noncommercial 1.0.0 regardless of what
these headers say. They are a frozen record of bytes a database has hashed,
not a statement about licensing. `LICENSE` and `LICENSING.md` are
authoritative.

## Adding a migration

New files take the current PolyForm header, since nothing has hashed them
yet. After adding one:

```bash
python3 scripts/lock-migrations.py
```

That records its checksum in `migrations.lock.json`. The lockfile is what
`scripts/lib/test_migrations_are_immutable.py` compares against, and it only
ever gains entries - it refuses to rewrite one, because rewriting is exactly
the mistake it exists to catch.
