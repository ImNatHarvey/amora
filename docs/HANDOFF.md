# Handoff

Context bridge for fresh sessions. Everything structural lives in
`00-architecture.md` and `02-design-system.md` — this file is only what those
don't say. Last updated for the Phase 2 commit.

## Where we are

Phases 0 and 1 are complete and accepted on device. **Phase 2 is written, tested,
applied, and verified on the phone — but NOT accepted.** One thing is left:

**Acceptance needs real places.** The criterion is "real, currently-open places";
all 15 rows are still `test-*`. See "Seed data" below. Nothing else blocks it.

> **The way that debt gets paid changed on 2026-08-05.** It stood open on the
> assumption that a row costs a journey, so the catalogue cost an expedition nobody
> booked. Nat ruled out fieldwork entirely and asked for the alternatives; a
> generated catalogue was considered and rejected outright (it breaks D3, §10.4 and
> CLAUDE.md's hard rule, and publishes invented prices attached to real named
> businesses). What survived is **§10.4a: the catalogue is buildable at a desk** —
> the free public layer from resident knowledge plus OpenStreetMap coordinates, and
> priced places by phone, both of which §10.4 already sanctioned and neither of
> which had ever been written up.
>
> **Nothing was weakened to get there.** No decision reversed, no invariant
> reworded, no phase moved. The target dropped from 15 places to 8 because the
> *cost* of a verified row fell, not the standard it must meet. `supabase/seed/DESK-CHECKLIST.md`
> is the procedure.

**In the meantime, `/ideas` ships.** `retrieve_activities` needs no curated place,
so "what could we do with ₱200 and what we own" works today on the 16 real activity
rows and the resource picker's output. Home leads with it, because it is the button
that works; "Plan something" is still there and still needs the catalogue. Details
in `00-architecture.md` §8 under Phase 2 — including the line it must not cross,
which is that Ideas answers *what* and never *where*.

**This is the first thing worth a device run since the Phase 2 verification.**
Check `/ideas` and `/dev/tokens` in dark mode at 1.3× font scale.

## Phase 3 — built, needs one secret

Everything except the model call is deployed and verified: four tables with RLS,
`cost_generated_plan`, the `generate-plan` Edge Function, the Dart repository and
models, and a "Generate with AI" button beside the Phase 2 builder on identical
input.

**Outstanding: `GEMINI_API_KEY`.** Free, two minutes, `aistudio.google.com/apikey`,
then `npx supabase secrets set GEMINI_API_KEY=... --project-ref eyeipcislyrsxnogyxas`.
Until it is set, the function answers 503 with exactly that instruction —
confirmed against the live endpoint, not assumed.

`GEMINI_MODEL` is also a secret, defaulting to `gemini-2.5-flash`. **If the first
call returns 404, set that secret rather than editing the function** — the error
message says so too. Model names move faster than deploys and D8 makes the model a
config choice.

Gotchas found building it, worth not rediscovering:

- **`cost_generated_plan` first omitted `slug` from each stop**, which
  `Place.fromMap` requires. It would have thrown on the first generated plan —
  and only once a key existed, which is the worst time to find it. Fixed in
  `20260805052510`. **Both composers must return the same stop shape**, field for
  field; that is what lets one Flutter model render either.
- **`plan_cache` has RLS on with zero policies**, which is how Postgres spells
  "service role only". It is not a mistake and does not need a policy added.
- **Rejection logging goes to the Edge Function console**, prefixed
  `PLAN_REJECTED`. Free-tier retention is short — copy anything worth keeping.

## Review pass — what it found

Run after Phase 3 landed, because three phases had gone in fast. Supabase security
advisors came back clean: the only two items are `plan_cache` having RLS with no
policies (that *is* "service role only") and leaked-password protection (Pro-only,
D7, permanently deferred). No missing RLS, no exposed function, no unindexed FK.

Three things that could have produced wrong money or stale data, all fixed:

- **Party size had two homes** — a constant in each of the two repositories, plus
  `= 2` defaults in two models. That is the multiplier turning per-person prices
  into party totals (§9). Had they drifted, the crude builder and the model would
  have reported different totals for the same plan — the exact bug §9 was written
  to end. Now `Party.size`, in one file.
- **The plan cache could never invalidate.** `placesVersion` was hardcoded to `1`,
  so the column that exists to evict stale plans never changed: correct a price,
  re-import, and the old total is served forever. Now reads
  `public.places_version()`, which moves with `max(verified_at)` and the row count
  — no new column, because the importer already stamps `verified_at` on every
  upsert. **Verified: a re-import moves it by ~458,000.**
- **`_pesos` was duplicated byte-for-byte** across two screens. Not ordinary
  duplication — it encodes the `zeroIsFree` rule learned by getting it wrong three
  times on a device, so the two copies could have been fixed apart. Now
  `lib/util/format.dart`, tested directly for the first time.

Also: `_ErrorRetry` deduplicated into a new `lib/ui/`, the 641-line plan screen
split into three files, and a redundant index on `plan_cache.constraint_hash`
dropped (the `unique` constraint already indexes it).

**Recorded, not fixed:** `places_lat_lng_idx` cannot serve the haversine filter —
no btree can answer a distance predicate. Harmless at 300 rows, so it stays, but
§5 no longer implies distance filtering is indexed. If it ever hurts, the answer
is a bounding-box prefilter, not another index.

50 tests, up from 41, with all 41 unchanged — the refactor was behaviour-preserving
and the old suite is the proof.

Everything else passes: `flutter analyze` clean, 23 tests green, the migration
applied, the SQL assertions (haversine, fare symmetry, past-midnight hours)
verified against the live database, and the full flow driven on the S25 Ultra in
dark mode at 1.3× font scale with zero render overflows.

**Pre-flight for the data run, both done and both clean:**

- **Per-person pricing verified on device.** ₱400 party budget renders "3 stops
  from Bunlo for 2", "₱200–₱400 each" on the priced stop, and Total ₱400 — the
  same plan that displayed ₱200 before the fix. Free places correctly take no
  "each" qualifier. 186 ms, no overflows.
- **The importer round-trips the two new columns.** A `verified_on` date and an
  `is_per_person = false` were pushed CSV → generated SQL → database and read
  back intact, then reverted. The pipeline he will run on return works with the
  new shape; he is not going to discover an importer bug at 11pm.

Measured on device: **202–340 ms** end to end including the Manila↔Tokyo round
trip, against 11.9 ms of server execution. The 400 ms criterion has room.

**Do not start Phase 3 until real data is in.**

## Scope is settled — §12. Stop theorising, go collect data.

Nat asked directly whether he is designing three phases ahead while sitting on 15
fake places and zero users. **He is, and the answer is yes, stop.**

The scope questions were worth answering *once*, because writing the line down is
what stops it recurring — and every one of them turned out to need **no schema
change, no new phase, and no code**. Deferring them costs nothing. That is the
tell: work that costs nothing to defer is work that should be deferred.

The stronger point: **Phase 2's acceptance criterion has never been met.** There
is no evidence yet that the core product is useful, because it has never run on a
real place. Designing Manila day trips before knowing whether a Bocaue Saturday
works is optimising a hypothesis nobody has tested.

The one-line boundary, in case a future session drifts: **Amora plans time within
a place you are already in.** "Day 3 in Manila with ₱500" is Amora and needs only
data. "Plan my Cebu trip" is a different product where our moat is worth nothing —
at trip scale a ₱25 tricycle fare is 0.17% of the budget instead of 12%.

**Next action is `supabase/seed/DESK-CHECKLIST.md`, not this file.** It was the field
checklist until 2026-08-05; most of the first eight rows no longer need a journey.

## Review findings — read before the data run

A full repo review found one live bug and settled two conventions. Both are now
in `00-architecture.md` §9; the doctrine behind them is §10 and §11.

**Totals were wrong by up to 2×.** The checklist defined `price_min` as "one
drink, one serving" (per person) while `build_simple_plan` summed those and called
the result the plan total — the device run's "Total ₱200 / budget ₱200" understated
a couple's real cost. **No document stated the convention anywhere.** Settled:
**money is per person, totals multiply by `party_size`**, and the budget always
means the whole outing. `transit_fares.is_per_person` handles the fare case, where
a jeepney charges each passenger and a tricycle special trip charges once.

**Phase 7 is a filtered list, not a feed** — and `CLAUDE.md`'s not-building list
already said "community feed", so this records reasoning behind a line that was
already there. Ranking specifies behaviour: rank by recency and people optimise
for photos, which costs the price data that makes a shared plan worth anything.

**Web search is a research aid, never a source.** Leads live in
`supabase/seed/candidates/` with columns deliberately incompatible with
`places.csv`. Verified: pasting them in exits 1 on `assertHeaders`. That is the
guard — a mechanism, not a habit.

**Seed-as-hypothesis holds, with one thing to remember:** stale hours are
*self-concealing*. The couple hits a locked door, abandons the plan, never
completes it, so no report is written and nothing is corrected. Hence closure
reports do not require a completed plan; price reports do. Correction is
**additive** — community values go in their own columns, and the hand-verified
value is never overwritten.

**It does not lower the bar on collection.** The correction loop needs completed
plans and a wrong seed prevents completion, so bad rows are abandoned rather than
fixed. The target is now 8 rather than 15, and that is a statement about what a row
*costs* (§10.4a), not about what one has to be worth. A ninth row invented to reach
a round number would be worth less than nothing.

## The intake is a conversation now — decided, don't reopen

Nat is building an **agent UI**: type what you want, constraints appear as
editable chips, then a plan. The docs previously specified a structured form
throughout. I argued for the form and was overruled; both sides are recorded in
`00-architecture.md` §9 and D10 so it does not get relitigated.

**The one rule that makes it affordable:** free text is reduced to the existing
constraint record *before* anything is hashed (§7 step 0), so `plan_cache` keys on
exactly what it always keyed on. Chat is quarantined to one cheap, retrieval-free
call at the front, and a tapped starter chip skips even that. **Never let raw
utterance text into a cache key** — that is the whole reason this works.

Roadmap changes that followed:

- **Phase 3 is unchanged** and still runs off the Phase 2 structured intake.
  Generation gets proven against a boring fixed input before language
  understanding is added, so a wrong plan has one suspect, not two.
- **New Phase 3b — conversational intake.** Extraction Edge Function,
  `intake_cache`, chat UI. Numbered `3b` to avoid renumbering 4–10 across three
  docs.
- **Phase 4 extended** to the result screen as pictured: place detail rendering
  `place_notes` (which had existed since Phase 0 with no renderer — a real hole in
  D2's claim to replace the Reddit tab), plus embedded DIY tutorial videos.
- **`plan_request/` is not thrown away.** It becomes the substrate the chat sits
  on, the fallback when extraction fails, and the only way to test retrieval
  without a model in the loop.

**Dependency flagged, not added:** embedding needs `youtube_player_iframe` (on
official `webview_flutter`) at Phase 4. **Check the Kotlin Gradle Plugin first** —
that is what got `flutter_image_compress` removed at Phase 0. Keep the
`url_launcher` "open in YouTube" fallback; it is the only thing that works for an
embed-disabled video, which the field checklist now screens for at collection.

### What the device run caught

Three instances of one mistake, invisible to every widget test because they were
all about *wording*, and invisible on the placeholder data until a plan with no
fares actually rendered: `_pesos(0)` returned `'free'` unconditionally, so the
screen read "places ₱200 · fares **free**", "budget **free**" and "none fit
**free**".

The rule now encoded in `_pesos(cents, {zeroIsFree})`: **"free" belongs wherever
₱0 is the price of something** — a place, a leg, a plan total, where the design
system's "free is good news, never muted" applies (docs 02 §2). **It does not
belong where ₱0 is an addend in a breakdown or a constraint being echoed back**,
where it reads as a category rather than an amount. "Total free" is right;
"fares free" is not.

Worth remembering for Phase 4, which renders far more money than this screen.

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

**Replacing them is now a desk job.** Target 8 across at least 3 barangays: layer 1
is the free public layer — plazas, parks, riverside, church grounds, covered courts,
the market — recorded from what Nat already knows first-hand, with coordinates off
OpenStreetMap and `verified_on` set to the honest date he was last actually there.
Layer 2 is priced places by phone, three questions and ninety seconds each. Full
rules and the limits of each: `docs/00-architecture.md` §10.4a. Procedure:
`supabase/seed/DESK-CHECKLIST.md`.

**What a phone call cannot reach** is `place_notes` — nobody describes their own
second floor as having no lift. A phoned row is a real row and a thinner one; the
notes get filled in the day he happens to be there.

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

**`supabase/seed/DESK-CHECKLIST.md` is where collection starts now.**
`FIELD-CHECKLIST.md` remains the phone-friendly capture list for rows a desk cannot
reach — field order, the mandatory-column traps, the fare-ride instructions, and the
shared import sequence both checklists use. Take that one out; leave this file at the
desk.

**Two traps were found in the field copy during review and are now fixed there.**
The desk sequence generated `seed.sql` *before* deleting the placeholders, but the
placeholders live in the CSVs — so the apply put all 15 straight back. And the
suggested barangay split gave every barangay 3+ places, which lets a whole plan sit
inside its origin with every leg a walk and `fare_for` never called: the exact
failure the spread section exists to prevent. The rule that fixes it is **one
barangay with no more than 2 places, and start the acceptance run there.**

**Real:** `resource_catalog` (30 rows) and `transit_fares` (15 real barangay
routes — Poblacion, Turo, Bunlo, Lolomboy, Duhat, Wakas, Batia, plus Marilao and
Balagtas). `activities` (16) are generic and fine.

> ⚠️ **`transit_fares.is_per_person` is `true` on all 15 rows, and on the 9
> tricycle rows that is an unverified default rather than a finding.** The column
> was added after those fares were collected and nobody recorded which rate was
> quoted. A tricycle special trip charges once for the vehicle, so any of those
> rows that was a special trip currently doubles for a couple. Jeepney rows are
> safe — a jeepney always charges per passenger.
>
> The nine routes are a **tick-box riding list in `FIELD-CHECKLIST.md`**, with
> fares, so they are in hand while out rather than only recorded here.
> `verified_at` is also null on all nine — nothing currently records that anyone
> has ridden any of them.

Wipe the placeholders — **from the CSVs first**, or the next import restores them:

```sql
-- only after places.csv and place_notes.csv are clean and seed.sql has generated
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
- **`comment on function` and `grant` need the full argument list** when two
  overloads of a name exist, or Postgres errors with "function name is not
  unique". When a function gains a parameter, `create or replace` makes an
  overload rather than replacing — **drop the old signature first**.
- **`node ... --out /dev/null` creates a literal `nul` file on Windows**, since
  Node writes the path rather than the device. Use a scratch path instead.
- Errors reaching the UI must go through `RepositoryException`; GoTrue will
  otherwise surface a raw JSON blob to the user.

## Coverage — a release gate, not a phase

**The app ships nationwide; only the data is Bocaue.** Nothing in the code is
city-specific, so a build installed anywhere works and finds nothing.

Not live yet: distribution is `flutter run` and hand-passed APKs, and profile
setup fixes city to Bocaue. Every user was handed the app personally, so there
are no uncovered users by construction.

**It goes live the moment an APK reaches someone Nat did not hand it to.** Before
that happens: say "Amora only knows Bocaue" *before* onboarding finishes, never
show a bare empty result screen, and capture where the user is in one tap — it is
the only signal that answers "which city next". Full reasoning in §12.5.

**Uncovered users should not be told to add their own places.** RLS makes it safe
(quarantined by invariant 5), but a user entering their own café and being shown
it back has a notes app, not Amora — the promise is that *we already knew*.
User-submitted stops stay what Phase 5 says they are: adding a missing stop inside
a covered city.

## Deferred, deliberately

Google sign-in (needs Cloud OAuth setup), password reset, account deletion,
settings screen, `profiles` DELETE policy, GIN index on
`activities.required_resource_ids` (pointless at 16 rows). `flutter_image_compress`
was removed — it applies KGP, which future Flutter refuses to build; re-add at
Phase 6.

`geolocator` is installed and still unused: Phase 2 asks for a barangay instead,
and GPS arrives with the map in Phase 4. `profiles.home_lat`/`home_lng` are
likewise still never written by anything.

~~Dark-mode `primary` and `error` converge.~~ **Fixed 2026-08-05**, ahead of Phase 4
rendering money in colour. The dark error family is overridden to an orange-red hue
so the two roles differ by hue rather than by nothing, and over-budget now carries
`tokens.costOverBudgetIcon` as well — colour alone fails for red-green colourblind
users at any hue. Light mode untouched. `docs/02-design-system.md` §2 and
`test/theme_test.dart`.
