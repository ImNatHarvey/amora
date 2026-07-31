# Seed data

These CSVs are the source of truth for Amora's curated local data. Their git
history *is* the data's history. Schema lives in `../migrations/`; data lives here
— see `docs/00-architecture.md` §6 for why the two are kept apart.

## Filling them in

Each file ships with three `EXAMPLE` rows showing the format. **Delete them and
replace them with real, verified rows.** The import script always skips any row
whose key starts with `EXAMPLE`, so an untouched template can never seed fake data.

Phase 0 target: **15 places**, **12–15 activities**.

Fill them in this order, since later files reference earlier ones:

1. `resource_catalog.csv` — things a user might own (picnic mat, speaker, ...)
2. `places.csv` — the moat. Real names, real prices, verified opening hours.
3. `activities.csv` — references resource slugs from step 1
4. `transit_fares.csv` — real jeepney and tricycle fares
5. `place_notes.csv` — lived experience; references place slugs from step 2

## Formats the script handles for you

**Money is in pesos, not centavos.** Write `180` or `180.50`; the script converts
to the integer centavos the database stores. Never write `18000`.

**Opening hours** use a compact grammar, converted to jsonb on import:

```
mon-sun 10:00-22:00
mon-fri 10:00-22:00; sat-sun 08:00-23:00
mon,wed,fri 17:00-21:00
mon-sun 24h
```

Days are `mon tue wed thu fri sat sun`. Ranges (`mon-fri`), lists (`mon,wed`), and
segments separated by `;` all work. **Omit days the place is closed** — a day that
is never mentioned is closed.

**Required resources** on an activity are pipe-separated slugs from
`resource_catalog.csv`, e.g. `picnic-mat|speaker`. Leave blank if none. An unknown
slug aborts the import rather than seeding an empty requirement list.

**Quote any field containing a comma:** `"12 Real St, Corner Two"`. Without quotes
the comma starts a new column, and the import aborts rather than shifting your data
one column to the left.

**`source_label` is a note's identity within its place**, not a category. Two notes
on the same place need different labels (`visit-2026-07-seating` and
`visit-2026-07-hours`, not `visit-2026-07` twice) — notes upsert on
`(place, source_label)`, so a repeat would overwrite rather than add. The import
refuses duplicate keys instead of letting that happen.

## What the import refuses to do

The script validates before it emits any SQL, and fails with a file and line
number. It will not run if:

- a header has a missing, misspelled, or unrecognised column
- a row has more or fewer fields than the header (usually an unquoted comma)
- two rows share the same natural key
- an activity references a resource slug that does not exist

Each of these would otherwise corrupt data silently, which is worse than failing.

## Importing

```sh
node supabase/seed/csv_to_sql.mjs --out seed.sql   # generate
node supabase/seed/csv_to_sql.mjs                  # or print to stdout
```

Then apply the SQL to the project (via the `execute_sql` MCP tool in a Claude Code
session, or `psql`). Every statement is an upsert keyed on a natural key, so
re-running after editing a row **updates** that row — it never duplicates. Editing
a price and re-importing is the normal way to correct data.

Changing a row's `slug` orphans the old row, since the slug is the identity. Rename
deliberately, and delete the stale row by hand if you do.

## Current state: placeholder places

`places.csv` and `place_notes.csv` currently hold `test-*` / `(TEST)` stand-ins,
seeded to prove the pipeline works. They are **not** verified Bocaue data. Replace
them with real rows, then clear the stand-ins:

```sql
delete from public.places where slug like 'test-%';   -- notes cascade
```

`resource_catalog.csv` and `transit_fares.csv` hold real values and need no such
cleanup, though the fares have a blank `verified_at` until you have ridden each
route (D5).
