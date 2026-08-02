# Handoff

Context bridge for fresh sessions. Everything structural lives in
`00-architecture.md` and `02-design-system.md` — this file is only what those
don't say. Last updated for the Phase 2 commit.

## Where we are

Phases 0 and 1 are complete and accepted on device. **Phase 2 is written, tested
and applied, but NOT accepted** — two things are outstanding, in this order:

1. **It has never run on the phone.** Wireless debugging was off during the
   session that built it, and Nat has **deliberately deferred** the device check
   until the phone is back on the network — do not treat it as blocking other
   work, and do not nag. Recovery steps are under "Test device" below.
2. **Acceptance needs real places.** Its criterion is "real, currently-open
   places"; all 15 rows are still `test-*`. See "Seed data" below.

Everything else passes: `flutter analyze` clean, 21 tests green, the migration
applied, and the SQL assertions (haversine, fare symmetry, past-midnight hours)
all verified against the live database.

**Do not start Phase 3 until 1 and 2 are done.**

## Phase 2, in one paragraph

The app calls one Postgres function, `build_simple_plan`, and renders what comes
back. That function retrieves curated places open at the requested time within
budget and radius, takes the 3 nearest it can afford, and costs every leg. Only
`build_simple_plan` is throwaway — Gemini replaces it at Phase 3 and calls
`retrieve_candidates`, `fare_for` and `haversine_m` unchanged. Rationale is in
`00-architecture.md` §4a; don't re-litigate it here.

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

### Getting wireless debugging back after a reboot

Samsung turns **Wireless debugging off on every reboot**, so this is a recurring
chore, not a fault. Work down the list; stop as soon as `flutter devices` sees
the phone.

1. **Phone:** Settings → Developer options → **Wireless debugging → ON**.
2. **Same Wi-Fi, and not a guest network.** Client isolation (common on guest
   SSIDs and some mesh setups) blocks both mDNS and the direct connection, and
   looks exactly like the phone being off.
3. **Try the saved name first:**
   `adb connect adb-R5CY224851B-4mLefi._adb-tls-connect._tcp`
4. **If that prints `cannot resolve host` — re-pair from scratch.** The name only
   resolves while the phone is advertising it over mDNS, and the pairing is
   dropped by a factory-level toggle or an OS update.
   - Phone: Wireless debugging → **Pair device with pairing code**. It shows an
     `IP:PORT` *and* a six-digit code. This port is **not** the same as the one
     on the main Wireless debugging screen.
   - `adb pair <ip>:<pairing-port>` — paste the code when prompted.
   - `adb connect <ip>:<connect-port>` — the port from the **main** screen.
5. **If mDNS is the specific problem** (pairing works, the name never resolves):
   - `adb mdns check` reports whether the discovery backend is running at all.
   - `adb mdns services` lists what it can currently see.
   - `adb kill-server && adb start-server`, then retry step 3.
   - Still dead: **use the `IP:PORT` form and move on.** It works identically;
     it just changes on reboot, which is the only reason the mDNS name is
     preferred. Do not spend a session fixing mDNS.
6. **"more than one device"** — two connections to the same phone.
   `adb devices` then `adb disconnect <the stale one>`.
7. Confirm with `flutter devices`, then `flutter run`.

If the phone appears in `adb devices` as `unauthorized`, the trust prompt is
waiting on the phone screen — unlock it and accept.

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

**What Phase 2 revealed about what the fieldwork needs.** Building first was
supposed to answer this, and it did:

- **Barangay is load-bearing, not decorative.** It is the only key fares have, and
  it is what `origin_areas` builds a coordinate from. A place with a blank
  barangay can be retrieved but never costed. Fill it every time.
- **Blank `opening_hours` makes a place invisible.** `is_open_at` returns false for
  null hours, by design — "currently open" cannot be promised about hours nobody
  checked. An unverified place is better left out of the CSV than added with the
  column empty.
- **Places that shut after midnight are now expressible**: write `fri 20:00-02:00`
  against the day it *opens*. Record these; an evening app needs them.
- **Intra-barangay fares are missing entirely** — the highest-value gap. Decided:
  collect same-barangay rows (`Poblacion → Poblacion, tricycle, ...`), which need
  no schema change. **Do not widen the walk threshold instead** — the reasoning
  is in `00-architecture.md` §9 and it was considered and rejected, not
  overlooked. Note the distance ridden alongside each fare.
- **Spread matters as much as count.** The placeholders all sit in Poblacion, so
  every generated leg is a walk and the fare path is exercised only by SQL
  assertions. The builder takes the 3 nearest affordable places, so 3+ places
  within 800 m of the origin means no fare is ever looked up. Target **at least
  3 barangays, max ~5 places in any one** — suggested split Poblacion 5, Turo 4,
  Bunlo 3, Lolomboy 3. All six pairs among those four already have fare rows.

**`supabase/seed/FIELD-CHECKLIST.md` is the phone-friendly capture list** — field
order, the mandatory-column traps, and the fare-ride instructions. Take that out;
leave this file at the desk.

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
- **`AppTheme.light` / `AppTheme.dark` are getters, not methods.** `AppTheme.light()`
  fails to compile with a confusing "method 'call' isn't defined" error.
- **`apply_migration` cannot read a file** — the SQL is passed inline, so the
  committed file and what was applied are two copies. Verify behaviour with
  `execute_sql` afterwards rather than assuming they match.
- Errors reaching the UI must go through `RepositoryException`; GoTrue will
  otherwise surface a raw JSON blob to the user.

## Deferred, deliberately

Google sign-in (needs Cloud OAuth setup), password reset, account deletion,
settings screen, `profiles` DELETE policy, GIN index on
`activities.required_resource_ids` (pointless at 16 rows). `flutter_image_compress`
was removed — it applies KGP, which future Flutter refuses to build; re-add at
Phase 6.

`geolocator` is installed and still unused: Phase 2 asks for a barangay instead,
and GPS arrives with the map in Phase 4. `profiles.home_lat`/`home_lng` are
likewise still never written by anything.

**Dark-mode `primary` and `error` converge** (`#FFB1C6` vs `#FFB4AB`). Phase 2's
screen is unstyled so it does not bite yet, but Phase 4 renders money in colour
and an over-budget total has to be unmistakable. Fix it during Phase 3 at the
latest — it gets harder once screens depend on both.
