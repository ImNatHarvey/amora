# Handoff

Context bridge for fresh sessions. Everything structural lives in
`00-architecture.md` and `02-design-system.md` — this file is only what those
don't say. Last updated at `89ca8b8`.

## Where we are

**Phase 0 and Phase 1 are complete, accepted on device, and pushed** (`89ca8b8`,
`master` in sync with origin). **Phase 2 — retrieval, no AI — is next.**

Phase 1 shipped email auth, profile setup, the resource picker, a repository
layer, and an auth-aware GoRouter redirect ladder. 10 widget tests pass against
in-memory fakes.

**Phase 2 is blocked on data, not code** — see "Seed data" below.

## Environment

- Windows 11, PowerShell. Repo at `C:\Users\jharv\amora`.
- Flutter 3.44.8 / Dart 3.12.2. The app is at `apps/mobile/` — **every** `flutter`
  command runs from there, never the repo root.
- Node 24 available (`npx supabase` needs no global install). No Python. No
  global Supabase CLI.

## Supabase

- Project ref `eyeipcislyrsxnogyxas`, Postgres 17, free tier.
- **Region is `ap-northeast-1` — Tokyo, not Singapore.** Worth knowing before
  anyone reasons about latency from Manila.
- Schema changes go through `apply_migration`; seed data through `execute_sql`
  (`00-architecture.md` §6). **`apply_migration` stamps its own version**, which
  will not match your local filename — rename the file to match the ledger
  afterwards or a later `supabase db push` will try to replay it.
- Email confirmation is currently **OFF** so signup logs straight in. Must go back
  on before real users.

## Test device

Samsung Galaxy S25 Ultra (SM-S938B), Android 16 / API 36, over **wireless
debugging** — the USB cable is charge-only. Stable id:
`adb-R5CY224851B-4mLefi._adb-tls-connect._tcp` (use the mDNS form; the IP-and-port
form changes on reboot).

**The emulator is abandoned** — unstable across several sessions. Do not suggest
it. Full rationale and the flagship-flatters-us caveat: `00-architecture.md` §3.

## Hard rules

- **₱0, no credit card.** Already ruled out: Google Maps (billing account),
  Cloudflare R2 (card), and Supabase leaked-password protection (Pro Plan — the
  security advisor flags it permanently; do not chase it).
- **Never invent local data.** No places, prices, fares, opening hours, or
  tutorial URLs from model knowledge. Ever. The curated database is the whole
  business (D3). Blank templates and obviously-fake `EXAMPLE` rows are fine;
  plausible-looking invented rows are not.
- **Claude does not commit or push by default** — print the commit messages as
  copyable blocks and Nat applies them in VS Code. (He sometimes authorises it
  explicitly in-session; absent that, print and stop.)
- Commits carry no Claude attribution — `.claude/settings.json` sets
  `includeCoAuthoredBy: false`.

## Seed data — placeholders, must be replaced

All 15 rows in `places` are `test-*` / `(TEST)` stand-ins with invented
coordinates, prices and hours. `place_notes` likewise. They exist to prove the
import pipeline, nothing more.

**Real:** `resource_catalog` (30 rows) and `transit_fares` (15 real barangay
routes — Poblacion, Turo, Bunlo, Lolomboy, Duhat, Wakas, Batia, plus Marilao and
Balagtas). `activities` (16) are generic and fine.

Wipe the placeholders with:

```sql
delete from public.places where slug like 'test-%';   -- notes cascade
```

CSVs are the source of truth in `supabase/seed/`; the importer validates headers,
row widths, duplicate keys and unknown resource slugs, and refuses to run rather
than corrupt. See `supabase/seed/README.md`.

**Phase 2 can be built on placeholders but cannot be accepted on them** — its
criterion is "real, currently-open places".

## Gotchas already hit

- **Theme:** `ColorScheme.fromSeed` at runtime replaced the Material Theme Builder
  export. Seed is `#B4436C`; change `AppTheme.seedColor` and nothing else.
- **Boot order:** the router must not be built before `Supabase.initialize` runs
  (it reaches `Supabase.instance` and throws), and the GoRouter redirect must be
  **synchronous** — an `async` one renders a black screen while it awaits. Both
  are recorded in `00-architecture.md` §4 with a regression test.
- **Hand-inserted `auth.users` rows** need `''`, not `NULL`, in the token columns
  (`confirmation_token`, `recovery_token`, `email_change`, …) or GoTrue fails with
  "Database error querying schema".
- **`supabase_flutter` 2.16** wants `publishableKey:`; `anonKey:` is deprecated.
  The `sb_publishable_` format works fine despite the Bearer header.
- **Two adb connections** to the same phone cause "more than one device" — drop
  one before running.
- Errors reaching the UI must go through `RepositoryException`; GoTrue will
  otherwise surface a raw JSON blob to the user.

## Deferred, deliberately

Google sign-in (needs Cloud OAuth setup), password reset, account deletion,
settings screen, `profiles` DELETE policy, GIN index on
`activities.required_resource_ids` (pointless at 16 rows). `flutter_image_compress`
was removed — it applies KGP, which future Flutter refuses to build; re-add at
Phase 6. Dark-mode `primary` and `error` converge (`#FFB1C6` vs `#FFB4AB`) —
must be resolved before Phase 4 renders money.
