# Handoff

Context bridge for fresh sessions. Everything structural lives in
`00-architecture.md` and `02-design-system.md` — this file is only what those
don't say. Last updated for the Phase 6 commit.

## Where we are

**Every phase of the MVP is now built.** Phase 6 was the last one, and there is
no more code to write before the app is usable end to end. What stands between
here and a shippable MVP is **data and a phone**, not development.

Phases 0 and 1 are complete and accepted on device. Phase 3b was **accepted
2026-08-10**, and **Phase 3's three criteria were all met on 2026-08-12** — 20
generations with zero invalid IDs, a cache hit, and 58/58 totals recomputed
independently. **Phases 2 and 4 are code complete and neither is accepted**; see
the ledger below for what is outstanding and why.

> Phase 3 passing is narrower than it sounds and the distinction matters: it
> proves the *pipeline* holds — the model never named a place outside the
> candidate set, and no total was ever wrong. It says nothing about whether the
> plans are any good, because all 15 places are still `test-*`. That question
> belongs to Phase 2's criterion and needs real data.

**Phase 5 is complete**, and it is the first phase since 1 whose acceptance
criteria were actually *met* rather than deferred: nothing in editing needs a
real place to be true. Only the device run is outstanding.

**Phase 6 is code complete and both its written criteria are met in SQL** —
a two-stop plan completed to one memory and exactly two reports, and a closure
was accepted with no plan at all. Only the device run is outstanding. See
"Phase 6" below, and note the per-person division: it is the one line in this
phase that would have been wrong plausibly and silently.

**The honest next action is `supabase/seed/DESK-CHECKLIST.md`.** Not more code —
there is none left in the MVP — and not Phase 6b either, which is gated on report
volume that single-digit users will take months to produce. The seed is the entire
product for the whole MVP window (§10.5).

**Phases 2, 3 and 4 are blocked on the same thing: real places.** The criterion
is "real, currently-open places"; all 15 rows are still `test-*`. See "Seed data"
below. Nothing else blocks Phase 2 at all.

**A device run is owed and it now covers four phases.** Wireless debugging was
off on 2026-08-12 (Samsung drops it on every reboot — the ladder is under "Test
device"), so nothing since Phase 2's verification has been seen on hardware. One
session with the phone on clears Phase 3b's conversation, Phase 4's UI and DIY
tutorial, Phase 5's drag-to-reorder, and Phase 6's completion sheet. Three of the
bugs this project has shipped were invisible to every widget test and obvious in
the first ten seconds on the phone.

> **Nat decided on 2026-08-08 to build every remaining phase first and collect
> the data at the end**, having been told the risk and asked again. Recorded so
> it is not reopened as though it were an oversight. The argument against, for
> whoever reads this later: the correction loop needs completed plans, a wrong
> seed prevents completion, and "is a Bocaue Saturday any good" is the one
> question no amount of code answers. The mitigation is the ledger.

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

> **That ordering is a fact about the data, not a product direction**, and the
> distinction matters now that §13 is withdrawn. Ideas leads because it is what
> can be demonstrated on placeholder places — not because activities are the
> product. When the catalogue lands, revisit the ordering on its merits; doing so
> reverses nothing.

**What to check when the phone is back on**, in one pass, dark mode at 1.3× font
scale: `/ideas`, `/plan-request`, the `/intake` conversation, a saved plan
(drag-to-reorder, the clock, ✕, "Add a stop"), **"We did this" through to a photo
and a spend figure**, `/memories`, and `/dev/tokens`. That is four phases' worth of
outstanding device confirmation in one sitting.

## Deferred acceptance criteria — the ledger

**Read this before declaring anything done.** On 2026-08-08 Nat chose to build
every remaining phase before collecting seed data, so criteria will keep going
unmet by decision rather than by oversight. The risk of that choice is not that
any one item is forgotten; it is that nobody can say at the end *which* items
were skipped. This table is the answer. **Add a row rather than quietly passing
a phase.**

| Phase | Criterion not yet met | Unblocked by |
|---|---|---|
| 0 | ≥8 places across ≥3 barangays; all 15 rows are `test-*` | `DESK-CHECKLIST.md` |
| 2 | "real, currently-open places within 5 km", the ₱0 run and the ₱100–₱200 run | the same 8 places |
| ~~3~~ | ~~20 generations with zero invalid IDs; cache hit~~ | **MET 2026-08-12** — 20/20, zero refused, cache hit confirmed |
| ~~3~~ | ~~every total matches an independent SQL recomputation~~ | **MET 2026-08-12** — 58/58 plans, `verify-totals.mjs` |
| 4 | whether the *map* is useful | real coordinates; 15 invented ones draw a cluster and 72 m legs |
| 4 | "a DIY activity plays its tutorial in-app" | one real `tutorial_url` — the **code is done**, see below |
| 4 | on-device confirmation of the Phase 4 UI | Nat's phone was in use on 2026-08-08 |
| 5 | on-device confirmation of drag-to-reorder | same phone. Both *written* criteria are met; this is the extra check §3 requires of every phase |
| 3b | on-device confirmation of the conversation | the phone |
| 6 | on-device confirmation of the completion sheet, **and the compressed photo's actual byte size** | the phone. Both *written* criteria are met in SQL; the photo size is the one fact no test can supply, because `image_picker` compresses in native code that `flutter test` does not run |

**Phase 3b's own criteria are MET as of 2026-08-10** — 20/20 extractions, zero
catalogue names, both rephrasings cache hits, on `gemini-2.5-flash-lite`. Run
`node supabase/functions/extract-intake/acceptance.mjs` to reproduce.

**`GEMINI_API_KEY` is set**, and has been since before the Phase 3b run of
2026-08-10. Earlier revisions of this file called it "the most expensive row
open" and blamed four criteria on it; that was true when written and is not now.
Struck rather than deleted so nobody re-reads it as a live task.

**Phase 3's 20 generations: the deployed function was the blocker, and it is
fixed.** The run had errored 11 of 20 — diagnosed, not guessed: failures returned
in ~900 ms while successes take 20–30 s, and a sub-second failure is Gemini
rejecting instantly with a 429, which the **deployed** `generate-plan` flattened
to a 500 so the harness's retry never saw it. The fix had been written in
`index.ts` and never deployed. The post-Phase-6 review confirmed that by reading
the deployed bundle back (v5 had no `UpstreamError` class at all) and deployed
**v6**. See "Review pass, post-Phase-6" for the result of the re-run.

**Phase 5 is not in this ledger for its own criteria**, and that is the point:
editing is true or false regardless of whether a place is real, so it could be
finished. Every other open row above is waiting on 8 rows of data or on the phone.

What is left is one evening of desk work and one session with wireless debugging
on. Neither gets easier by being left later, and the first gates the only question
that matters — is a Bocaue Saturday any good.

## Phase 3 — Gemini generation. All three criteria MET 2026-08-12.

Everything except the model call is deployed and verified: four tables with RLS,
`cost_generated_plan`, the `generate-plan` Edge Function, the Dart repository and
models, and a "Generate with AI" button beside the Phase 2 builder on identical
input.

~~**Outstanding: `GEMINI_API_KEY`.**~~ **Set, and has been since before
2026-08-10.** If it is ever unset again the function answers 503 with the exact
`supabase secrets set` command — and since the post-Phase-6 review that sentence
reaches the app instead of being replaced by "check your connection".

`GEMINI_MODEL` is also a secret, defaulting to `gemini-2.5-flash`. **If a call
returns 404, set that secret rather than editing the function** — the error
message says so too, and now names the right secret per function
(`extract-intake` reads `EXTRACT_MODEL`, and its 404 used to send you to
`GEMINI_MODEL`, which it never consults). Model names move faster than deploys and
D8 makes the model a config choice.

**Run acceptance with two commands, in order:**

```
node supabase/functions/generate-plan/acceptance.mjs      # 20 generations + cache hit
node supabase/functions/generate-plan/verify-totals.mjs   # every total, independently
```

The first writes `.acceptance/phase3-acceptance.json`; the second reads it and
recomputes every plan from `places` and `transit_fares`. Neither uses
`cost_generated_plan` — that is the function being tested.

**Empty `plan_cache` first if you want the run to mean anything.** Otherwise most
of the twenty are cache hits replaying already-validated payloads, and the
zero-invalid-IDs result is close to vacuous:

```sql
delete from public.plan_cache;   -- a cache; the only cost is refilling it
```

### Two defects found closing Phase 3 out

Both were in Phase 3's own code, neither had symptoms yet:

- **The cache key collided across days.** `constraintHash` shifted the hour into
  Manila but read the day from UTC, so for any Manila time between midnight and
  08:00 the day was one behind — **Manila Sunday 02:00 and Manila Saturday 09:00
  hashed identically**. Opening hours are per day, so the second caller could have
  been served a plan composed for a day the places are shut. Fixed by deriving both
  the hour and the day from one Manila instant. Checked in both directions: the
  collision separates, and two requests that genuinely share a Manila day and
  bucket still merge — otherwise the "fix" would just be breaking the cache.
- **Party size had three hardcoded `2`s** in the Edge Function, the server-side
  twin of the Dart bug fixed the day before. Worse here: one fed the cache key and
  another fed the costing call, so a drift would have cached a plan under one party
  size and costed it for another. Now one `DEFAULT_PARTY_SIZE`.

**The plan tables are deliberately writer-less** until Phase 4 — see §8. Not drift.

**The cache key now has tests:** `npx deno test supabase/functions/generate-plan/`.
Deno is not installed globally; `npx deno@latest` works and is what the command
above resolves to. Nine cases, each written in **both directions** — a key
function can fail by merging things it should separate (wrong answers) or by
separating things it should merge (no caching at all, which the free tier cannot
afford), and a suite checking only one direction passes trivially if you make
every key unique.

The regression test was checked against the *pre-fix* code and fails there,
printing the two identical keys. A test that passes against both versions would
have been worth nothing.

`constraint_hash.ts` is a separate module for one reason: importing `index.ts`
starts a server, which would make the part of this function most needing tests
the hardest part to reach. The Edge Function imports from it, so there is one
copy, not two.

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
- **`process.exit()` in a Node script that used `fetch` trips a libuv assertion
  on Windows** — the process dies with exit 127 instead of the code it meant to
  return, because keep-alive sockets are still open. Set `process.exitCode` and
  return instead. Cost twenty minutes in the acceptance harness.

## Phase 4 — code complete; acceptance waits on data

Map, timeline, cost breakdown, save/reopen and place detail. The first commit
added **no new dependencies** — `flutter_map` 8.3.1, `latlong2` and
`url_launcher` were already in `pubspec.yaml`. The close-out commit added one,
deliberately and after checking (below).

**Routes moved.** `/plan` used to be the request screen; it is now `/plan-request`,
because `/plan/:id` is a saved plan. Also `/plans` and `/place/:id`.

**`place_notes` finally has a renderer.** The table has existed since Phase 0 and
nothing displayed it, which quietly undercut D2's claim to replace the Reddit tab
for four phases.

### The DIY tutorial player — built 2026-08-08

Deferred at first commit on the grounds that a webview that can play nothing
repeats the `flutter_image_compress` mistake. Closed once the dependency was
checked rather than assumed.

**`youtube_player_iframe` 6.0.2 is safe to depend on.** It pulls
`webview_flutter` 4.14.1 / `webview_flutter_android` 4.13.0, whose
`android/build.gradle.kts` applies **only `com.android.library`** — it has
migrated to AGP Built-in Kotlin and does *not* apply
`org.jetbrains.kotlin.android`. That is exactly the migration the Phase 0 note
told a future session to check for. **`flutter build apk --debug` succeeds**
(270 s), which is the only check that actually settles it. KGP still sits on the
plugin's `buildscript` classpath; it is vestigial and does not break the build.

**`tutorial_url` was unreachable, not merely empty.** The column has existed
since the Phase 0 schema, but `retrieve_activities` never selected it, so no
caller could have rendered a link even if one existed. Migration
`20260808152258` drops and recreates the function with the column added —
**adding a column to a return table is not a `create or replace`**, Postgres
refuses to change a return type, and the drop takes the grants with it so the
`revoke`/`grant` pair must be reissued with the full argument list.

Every existing caller was checked, not assumed:

- `cost_generated_plan` selects `a.activity_id` only — unaffected.
- `build_simple_plan` does `to_jsonb(a)`, so `candidate_activities` gained the
  field. That reaches the same `Activity.fromMap` the Ideas screen uses, so one
  model change served both surfaces.
- **`generate-plan`'s prompt emits `activity_id | title | category` and nothing
  else**, so the model's view did not widen. Worth stating plainly: widening
  what *retrieval* returns is not widening what the *model* is told. Invariant 1
  holds.

**Three render states, not two.** `tutorialRenderFor(url)` in
`lib/features/ideas/diy_tutorial.dart` returns `none` / `embed` / `linkOnly`,
because "no embed" and "no tutorial" are different facts: collapsing them would
either grow a dead button on the blank rows we ship today, or silently drop a
Facebook video somebody collected. It is a **pure function, separate from the
widget, for the same reason `constraint_hash.ts` is separate** — the embed path
needs a platform webview that `flutter test` does not have, so a test that could
only reach the rule through a widget could not reach it at all.

**The external "Watch the tutorial" action stays even when the embed works.** An
embed-disabled video fails *inside* the iframe, showing its error there; Flutter
never sees it, so there is no way to swap to a fallback after the fact. It has
to already be on screen.

**What is left is one URL.** All five `is_diy` rows have `tutorial_url` null and
that is the correct state — D5 names tutorial URLs among the facts that are
collected and watched, never generated, because a recalled video id renders a
dead player that looks exactly like a working one until it is tapped. Paste one
into `activities.csv`, re-import, and the criterion is met.

**Gotchas worth not rediscovering:**

- **`const StrokePattern.dashed(segments: [8, 6])` does not compile.** The
  package asserts `segments.length`, which const evaluation cannot do. Drop the
  `const` on the constructor and keep it on the list.
- **Models keep `sourcePayload`** so saving does not re-request. For a generated
  plan that would spend a second Gemini call *and* could return a different plan
  — the user would save something other than what they were looking at.
- **`plans.origin_area` exists because a reopened plan needs it.** The first leg
  starts at the origin, not at a stop.

## The Gemini free tier is 5 requests per minute. Measured, not assumed.

The first Phase 3b acceptance run hit 429 and said so exactly:

```
quotaId:    GenerateRequestsPerMinutePerProjectPerModel-FreeTier
quotaValue: 5
model:      gemini-2.5-flash
```

**Five per minute, per project, per model.** §7 already warned the quota was
"managed, not solved" at Phase 3b; this is the number.

What it means for the product, since §7 says a new utterance costs **two** calls
(extract, then compose):

- **~2.5 new plan requests per minute across all users**, not per user.
- A **tapped starter chip costs zero** — it skips extraction entirely. A
  `plan_cache` hit costs zero. An `intake_cache` hit costs zero.
- So the cache economics stop being a nicety and become the thing that makes the
  product usable at all. Anything that weakens them — free text in a cache key,
  a chip that calls the model — is a product-level regression, not a
  tidiness issue.

Two consequences already acted on:

- **Both acceptance harnesses pace at 13s** (~4.6/min) and retry 429 and 503.
  Unpaced, a run fails partway and reads as "the model got it wrong", which
  sends you looking at the prompt instead of the clock.
- **Both Edge Functions now pass an upstream status through** rather than
  flattening it to 500. A caller could not previously distinguish "wait 30
  seconds" from "this is broken" — and the acceptance harness's own retry never
  fired because it was watching for a 429 that had already become a 500.

**503 also happens** — Gemini reporting its own overload. Three of twenty on the
first run. It is transient and retried, not a fault.

## Extraction runs on its own model, and that was not cosmetic

`extract-intake` reads `EXTRACT_MODEL`, defaulting to **`gemini-2.5-flash-lite`**.
It deliberately does *not* fall back to `GEMINI_MODEL`: that secret may be set to
`gemini-2.5-flash`, and chaining to it would hand extraction the contended model
back and make the split do nothing.

**Why it exists:** `gemini-2.5-flash` could not complete twenty extractions.
Two runs were killed after 15–20 minutes having managed six and seven, with
fresh calls failing 503 "high demand" through three backoffs. The same twenty on
flash-lite finished in about five minutes with no retries at all. The Edge
Function logs show it plainly — v4 (flash) is a wall of 429s, v5 (flash-lite) is
solid 200s.

**Why it is also right on merit:** composing three costed plans from thirty
candidate rows is a judgement call; reading "under 200 tonight" into four typed
fields at `temperature: 0` is mechanical. The schema does the constraining, not
the model's cleverness.

**Composition stays on `gemini-2.5-flash`** — Nat's call, and the harder task
keeps the larger model.

## Phase 3b — conversational intake. ACCEPTED 2026-08-10.

**20/20 extractions, zero catalogue names, both rephrasings cache hits.**

The adversarial half behaved exactly as designed, and the interesting part is
what it kept rather than what it dropped:

| Utterance | Result |
|---|---|
| "take me to Starbucks in Manila" | nothing |
| "that café on the highway" | nothing |
| "plan my Cebu trip" | nothing |
| "we want to go to Jollibee" | nothing |
| "somewhere in Quezon City with ₱400" | **₱400 kept**, place dropped |
| "SM Bulacan this weekend" | **weekend kept**, place dropped |
| "Aling Nena's carinderia, tonight" | **tonight kept**, place dropped |

A named place is not a constraint; the rest of the sentence still is. That is the
behaviour §7 step 0 asks for, and it is not something the schema alone would give
you — it is the schema plus `origin_area` being validated against `known_areas`.

The legitimate half resolved correctly too: "we're in Turo, around ₱300" →
₱300 / Turo; "starting from Poblacion around 7pm" → Poblacion / 19:00;
"free date tonight, we have no money" → **budget 0**, which is the ₱0-is-a-real-
budget path (§9) surviving the model.

## Phase 3b — conversational intake, as built

The thread, starter chips, editable constraint chips, `intake_cache`, and the
`extract-intake` Edge Function. Migration `20260810071916`.

**Invariant 1 is enforced by shape here, not by checking.** The extraction
`responseSchema` has four typed fields — an integer, an ISO instant, one string
and an enum — so **there is no field a place name could occupy**. The one string
is `origin_area` and it must match `known_areas`, so "Starbucks", "the café on
the highway", "Manila" and "Cebu" all fail identically and become an unfilled
chip. The prompt carries no candidate rows at all, so there is nothing to leak
even in principle.

`extraction.ts` is a separate module for the same reason `constraint_hash.ts`
is: importing `index.ts` starts a server, which would make the part most needing
tests the hardest to reach. 14 tests, all of them hostile *model output* rather
than hostile user input — the user may say anything; what matters is that
nothing they say puts a name into a stored constraint.

**The cost argument, and the thing not to break:** a tapped chip **never calls
the model**. It is already a structured value and skips §7 step 0 entirely, so
the friendliest path is also the cheapest. There is a widget test asserting the
extraction repository is never called on the chip path — if that ever goes red,
the conversation has stopped being affordable and nothing on screen would show
it.

**Free text never reaches a cache key.** `plan_cache` still hashes the same
constraint record it always did; `intake_cache` keys on a SHA-256 of the
*normalised* utterance and stores only the digest and what it reduced to. The
sentence is not stored, not logged (`INTAKE_REJECTED` carries the hash, never
the text), and never hashed into a plan key.

**Normalisation is deliberately conservative** — lowercase, strip punctuation,
collapse whitespace, and nothing else. No stemming, no reordering, no stop-word
removal: merging two utterances that mean different things would serve wrong
constraints confidently, which is far worse than paying for one more extraction.
Tested in both directions, like the constraint hash.

**Gotchas worth not rediscovering:**

- **A `TextEditingController` created beside `showDialog` and disposed from
  `whenComplete` throws.** The future completes when `pop` is called, while the
  field is still on screen fading out — "used after being disposed". Let the
  dialog's own `State` own it. Caught by a widget test; it would have thrown on
  device too.
- **An indeterminate `LinearProgressIndicator` never lets `pumpAndSettle`
  return.** The intake state carried `busy` inside an `AsyncError.copyWithPrevious`,
  which retained `busy: true`, so the bar stayed up and the test hung rather
  than failed. The conversation now keeps its error as a field on the state and
  is always `AsyncData` — one place `busy` is read from, always the value last
  written.
- **`npx supabase functions deploy` needs its own auth** (`supabase login` or
  `SUPABASE_ACCESS_TOKEN`) and does not share the MCP connection's. Deploying
  through MCP means passing file contents by hand, which is how the deployed
  bundle and the repo can silently diverge — **redeploy verbatim from disk
  before committing**, or authenticate the CLI once and stop worrying about it.

## Phase 6 — completion & actuals. Code complete 2026-08-12.

Five migrations (`20260812095046`, `095154`, `095231`, `095556`, `095956`), one
repository, one sheet, one timeline screen. **No new dependency** —
`image_picker` was already installed and compresses natively, so
`flutter_image_compress` and its Kotlin Gradle Plugin stay out; the §8 note asking
for a check before re-adding it is answered "not needed".

**The per-person division is the thing to not break.** The sheet asks what the
*party* handed over; `complete_plan` divides by `plans.party_size` before storing
`place_reports.reported_cost_php_cents`, because 6b takes a median against
`places.price_min_php_cents`, which is per person (§9). Verified end to end: ₱400
party → ₱200 stored → 11% divergence from the seeded ₱180, which 6b correctly
leaves alone. **Store the party figure and every median doubles**, looking
entirely plausible. There is an explicit SQL assertion for exactly this, and a
widget test asserting the *screen* does not divide either — the bug that survives
both would be dividing twice.

**Three things a widget test cannot see, so they were verified in SQL as service
role:**

| Check | Result |
|---|---|
| one report per stop, cost stored per person | 2 stops → 2 reports, ₱200 and ₱225 |
| plan total derived, recomputed by hand | ₱975.01 = 400 + 450.01 + 35 + 90 |
| a completion of an already-completed plan | refused |
| `edit_plan` on a completed plan | refused |
| a stop or leg `seq` the plan does not have | refused, and so is an entry with **no** `seq` key |
| deleting or rewriting a report | `permission denied` |
| a second user reading/planting a memory or report | refused, five ways |
| uploading into another user's folder, or the bucket root | refused |
| **a closure with no plan at all** | **accepted — this must never require one** |

Each refusal was checked **as service role afterwards** to confirm the rows it
could not see really exist. A check run as the attacker cannot tell "blocked"
from "succeeded but invisible to me", which nearly produced two false passes in
Phase 5.

**"Active" had to be given a meaning.** §8 says a closure is reportable from an
*active* plan, and nothing in the codebase has ever set `status = 'active'` —
every saved plan is a `draft`. Decided: **active means saved and not yet
completed.** A `draft → active` transition was considered and rejected, because a
"we're heading out" tap the user can skip would silently block the one signal
§10.2 says we are structurally short of. `'active'` stays an unused enum value.

**Found by assertion, not by reading: `grant select, insert` is a no-op.**
Supabase ships `alter default privileges in schema public grant all on tables to
anon, authenticated`, so every new `public` table arrives with DELETE, UPDATE and
TRUNCATE already granted. The first Phase 6 migration claimed "no update or delete
grant" and did not have one. RLS held — a delete removed zero rows — but the
refusal was **silent** and the second layer was fiction. Migration `095956`
revokes properly, so it now errors.

> **`plan_edits` has the identical defect and is deliberately untouched.** Same
> blanket grants, same claim in its own comment, same RLS protecting it, so it is
> not a live hole. It is Phase 5's file and CLAUDE.md says flag rather than reach
> outside the phase. **One line when someone wants it:**
> `revoke update, delete, truncate on public.plan_edits from anon, authenticated;`

**Gotchas worth not rediscovering:**

- **A missing key defeats a range check silently.** `(e ->> 'seq')::integer not
  between 1 and n` is NULL when the key is absent, and NULL is not true — so an
  entry with no `seq` passed validation and then matched no stop, losing a figure
  the user had typed. Both conditions are now tested, and there is an assertion
  for the no-key case specifically.
- **A prefilled field submitted untouched is recorded as observed.** Known and
  accepted: the user *was* there, and it is conservative in the only direction
  that matters, since §10.5 needs >20% divergence to override. Confirmations pull
  the median toward the seed and can never invent a wrong price.
- **`cached_network_image` must be given `cacheKey: photoPath`.** The bucket is
  private so every read is a signed URL that expires; the cache keys on the URL
  by default, which would re-download every photo on every scroll while looking
  exactly like a working cache.
- **The completion sheet's controllers belong to its `State`**, not to the code
  calling `showModalBottomSheet` — the Phase 3b dialog gotcha, same shape.
- **A widget test viewport is 800 px tall**, so the sheet's money fields did not
  exist to tap until `tester.view.physicalSize` was raised. Same fix as
  `add_stop_screen`, same reason not to scroll instead.
- **An unpriced leg gets an empty field, not no field.** It is the highest-value
  input on the sheet: `transit_fares` has no row for that barangay pair, and the
  couple who just paid it is the only source that will ever exist (D5).
- **`memories.plan_id` is unique** so a double completion cannot duplicate the
  reports beside it. 6b takes a median over those, so a double tap would move a
  price further than §10.5's anti-gaming rules intend to allow.

**Left for Phase 6b, deliberately:** every rule in §10.5 that *reads* a report —
the median, the 20% threshold, the closure quarantine, the 30-day caps, the
provenance labels. Phase 6 writes the corpus; nothing reads it yet.

**One assertion plan is still in the database** (`PHASE6 ASSERTION PLAN`, on
`phase1@example.com`), completed, with a memory and two reports. Left on purpose:
it is a rendering fixture for the device run. Delete it afterwards if you want a
clean timeline.

## Phase 5 — editing. Complete.

Reorder, remove, retime, add a stop; `plan_edits` logged; user places
quarantined. Three migrations: `20260808155247`, `20260808155446`, and
`20260808163648` (the review fix below).

**Retime shipped a session late, and the gap is worth remembering.** The first
Phase 5 commit built reorder, remove and add, and `edit_plan` accepted `retime`
and was verified in SQL — but **nothing in Flutter ever called it**. Three of
the four edit types in §8's line were reachable. It looked finished from the
database side and from the test suite, because both were exercising a path the
user could not reach. **When a phase lists capabilities, check each one against
a UI affordance, not against a function signature.**

The clock button opens a bottom sheet (`retime_sheet.dart`): a Material time
picker plus duration chips. **The conversion is where this goes wrong
silently** — `showTimePicker` returns a Manila wall clock, the column stores
UTC, and combining them without `manilaToUtc` shifts every retimed stop eight
hours while the plan still renders perfectly plausibly. Verified against the
live database: 19:30 Manila stored as `11:30Z`, order and every fare unchanged.

**One recompute path, and that is the whole design.** `save_plan`'s item/leg
loop is now `write_plan_stops`, which `edit_plan` also calls. Do not reintroduce
a second copy: two would let a saved plan and an edited plan disagree about a
fare, which is the bug class this repo has already shipped twice (party size in
two files, `_pesos` in two screens).

**An edit sends the whole new stop list**, not a delta, and `edit_plan` returns
the whole recomputed plan. That keeps always-live editing at one round trip and
means the device never renders a total it computed.

**Phase 0 had already built most of the quarantine.** `places` has had
`source`, `verification_tier` and `submitted_by_user_id` since the first
migration; `places_read` has always returned curated rows plus your own; and
`retrieve_candidates` has filtered `verification_tier = 'curated'` explicitly
since Phase 2. Phase 5 added the insert policy Phase 0's comment promised, and
proved the rest.

**Five attacks, all refused** — and **every one verified as service role**. A
check run as the attacker is subject to the same RLS, so "zero rows" would mean
"blocked" and "succeeded but invisible to me" identically. That nearly produced
two false passes here.

| Attack | Outcome |
|---|---|
| Insert `verification_tier='curated'` | refused by the `with check` |
| Insert a row attributed to another user | refused |
| Promote own row to curated by UPDATE | refused — no update policy, no update grant |
| Edit another user's plan | refused |
| Delete rows from `plan_edits` | refused — append-only by omission |

**Do not grant `update` or `delete` on `places`.** The insert policy pins
`source`, `verification_tier` and `submitted_by_user_id`; an update grant would
be the same hole through a second door.

> **Correction, 2026-08-12: both *were* granted, and had been since Phase 0.**
> Not by anyone's edit — Supabase's default privileges grant every verb on every
> new `public` table to `anon` and `authenticated`, so this instruction described
> an intention rather than the database. RLS refused the writes, so nothing was
> exploitable, but the sentence above was not true when it was written. Migration
> `20260812112101` makes it true. The audit query is in `00-architecture.md` §5;
> re-run it whenever a table is added.

**`known_areas` is not `origin_areas`, deliberately.** An origin needs a
coordinate and the only honest one is the centroid of curated places. A new
place brings its own from a map tap, so it may sit in Duhat, Wakas or Batia —
barangays with fares but no places, and exactly where a missing stop is worth
adding. Free text was rejected because `fare_for` matches barangay by exact
string: one typo makes every leg to that stop unpriced forever, silently.

### What the review pass found, all fixed

- **`save_plan` and `edit_plan` disagreed about which city a plan is in.**
  `save_plan` resolved it through `profiles join places on p.city = pr.city`,
  which returns the profile's city *only if a place already exists there* and
  otherwise silently falls back to `'Bocaue'`; `edit_plan` read `pr.city`
  directly. For a user whose city holds no curated places the two diverge, and
  the symptom is not a wrong number — `save_plan` writes an `origin_area` from
  Bocaue's `origin_areas` and `edit_plan` then looks it up in a different
  city's, finds nothing, and raises on **every** edit. The plan becomes
  permanently uneditable. Unreachable today because profile setup fixes city to
  Bocaue (D1), which is exactly why it was worth fixing now: it arrives on the
  day coverage expands, which is the day nobody is looking at `save_plan`. Now
  one `plan_city()`.
- **`PlanEditor.addPlace` had its own copy of `_apply`'s body** — the same
  loading-with-previous, guard and invalidate. Third instance of the shape that
  produced the party-size and `_pesos` bugs. Now both go through `_send`.
- **`known_areas` returned `has_places` / `has_fares` and Dart discarded both.**
  Rather than drop columns, `has_fares` now warns in the add-stop picker: a
  barangay with no recorded fare gives a permanently unpriced leg, and the user
  should hear that while choosing rather than after the total comes back hedged.

**Tests added for what nothing was checking:** that an edit carries the model's
`note` and `activity_id` forward (had it regressed, every reorder would strip
the only thing the model authors — the plan would still render and still cost
correctly, and quietly be worth less), that a retime stores the right instant,
and the whole of `add_stop_screen`, which had no coverage at all.

**Gotchas worth not rediscovering:**

- **A widget test viewport is 800 px tall and a `ListView` does not build what
  is off-screen.** `add_stop_screen`'s submit button simply did not exist to
  tap. Raise `tester.view.physicalSize` rather than scrolling — scrolling drags
  across the map and starts a gesture instead.
- **`ReorderableListView.onReorder` is deprecated in Flutter 3.44** in favour of
  `onReorderItem`, which hands back a newIndex **already adjusted** for the
  lifted item. The old callback required subtracting one when dragging
  downwards. Doing both rotates the list by one on every downward drag. This was
  caught by `flutter analyze`, not by a test, and the tests now cover both
  directions.
- **Changing a function's return type needs a `drop`** — `create or replace`
  refuses. The drop takes the grants with it, so the `revoke`/`grant` pair must
  be reissued with the full argument list.
- **The placeholder coordinates are clustered**, so a cross-barangay leg can
  still be under the 800 m walk threshold and cost nothing. The first acceptance
  plan produced three free walks and exercised no fare at all. Pick stops more
  than 800 m apart when testing money — `Dessert Bar`/`Casual Diner` are 1,693 m
  apart with a ₱90 tricycle.
- **A place with null `opening_hours` is invisible to `is_open_at` anyway**, so
  a quarantine test on a fresh user place passes for the wrong reason. Give it
  hours and a near-origin coordinate first, so tier is the only thing left that
  can exclude it.
- **`00:00`–`23:59` is not "all day".** A test run at 23:59:27 Manila failed on
  27 seconds. The all-day form is `00:00`–`24:00`.

**Test accounts:** `phase1@example.com` and `phase5b@example.com`. Keep the
second — RLS cannot be tested in both directions with one user, and Phases 6 and
7 will need it.

**Their passwords are written down nowhere, deliberately** (see "No credentials
in documentation" below). To use one, reset it and keep the value only for that
session:

```sql
-- service role, via execute_sql
update auth.users
set encrypted_password = crypt('<a value you generate now>', gen_salt('bf')),
    updated_at = now()
where email = 'phase5b@example.com';
```

Most testing needs neither account: `set local role authenticated` plus
`set local request.jwt.claims` impersonates any user for RLS work without a
password at all, which is how the Phase 5 attack tests were run.

## Review pass, post-Phase-6 — what it found

Run after the MVP closed, before the seed-data run. Four findings, three of them
real bugs, one the fourth recurrence of this repo's signature failure mode.

**What was already healthy**, so nobody re-checks it: all 20 public Postgres
functions pin `search_path`, including both `SECURITY DEFINER` ones — no
escalation surface. `INTAKE_REJECTED` logs field *names* only, so the "user text
is never stored or logged" claim holds under inspection. No `TODO`/`FIXME`
anywhere.

### 1. Every Edge Function error was reaching users as "check your connection"

**The worst finding, and it made three earlier pieces of work inert.**
`functions_client.invoke` **throws** `FunctionException` on any non-2xx rather
than returning the body, and `guard` had no clause for it — so it fell to the
generic catch and became `'<fallback> Check your connection and try again.'`

| Server said | User read |
|---|---|
| 503 `GEMINI_API_KEY is not set… supabase secrets set…` | "Could not generate a plan. Check your connection…" |
| 429 `the free tier allows 5 per minute; try again shortly` | the same |
| 502 `The model produced no valid plan after a retry.` | the same |

So: both repositories' `data['error']` checks were dead for non-2xx (they can
only fire on an error inside a **200**, which neither function emits); the whole
`UpstreamError` effort in both Edge Functions was invisible to the app; and
`repository_exception.dart`'s own doc comment had always listed
`FunctionException` among the types it handled. On a tier capped at five requests
a minute, a rate-limited couple was being told to fix their wifi.

**Body before status, and a test caught that ordering.** The first fix checked
429/503 first — which passed its own test and broke the missing-key case, because
that message is served as a **503**. The one error carrying a fixable instruction
became the one you cannot act on. `guard` now reads `details['error']` first and
uses the status only when there is nothing to quote.

**`test/repository_exception_test.dart` is new, 13 cases.** `guard` decides every
error message in the app and had no test at all, which is how a missing exception
clause survived three phases.

### 2. The deployed `generate-plan` was stale — and that was Phase 3's blocker

Read back from the project: v5 had **no `UpstreamError` class at all**, no 429 or
503 branch, and a catch that returned 500 for everything. Exactly as this file
said, and confirmed rather than assumed. That is why Phase 3's acceptance failed
11 of 20 — sub-second failures were 429s flattened to 500, so the harness's retry
never fired.

Both functions are now deployed at **v6** and **read back and compared against
disk**, which is the check this file names as the hazard of MCP deployment and
which nobody had run.

### 3. `extract-intake`'s 404 told you to set the wrong secret

It said *"Set the `GEMINI_MODEL` secret"* while the function reads
`EXTRACT_MODEL` — and its own doc comment insists at length that it must never
fall back to `GEMINI_MODEL`. Doing what the error said would have done nothing.
Root cause: the local const was *named* `GEMINI_MODEL` while holding
`EXTRACT_MODEL`. Now `EXTRACT_MODEL`, and the shared helper takes the secret name
as a **required parameter** — a copied message can be wrong, a required argument
has to be passed.

### 4. `supabase/functions/_shared/` — because findings 2 and 3 *were* the drift

`UpstreamError`, `CORS`, `json()`, `callGemini`, the missing-key 503 and the
two-client auth preamble all existed twice. One copy learned about 429s and the
other did not; one copy's message was edited without its variable being renamed.

Now `_shared/http.ts` and `_shared/gemini.ts`, with `callGemini` parameterised by
model, secret name, schema and temperature. `upstreamErrorFor` is exported and
tested against fabricated responses — **7 new deno tests**, in both directions
(each caller's 404 must name its own secret and *not* the other's), because a
mapping that always said `EXTRACT_MODEL` would pass a one-sided test.

**Deploying `_shared` through MCP works**, and the trick is worth keeping: pass
the **functions directory** as the bundle root — files named
`generate-plan/index.ts`, `_shared/http.ts` — with `entrypoint_path` set to
`generate-plan/index.ts`. A `../_shared/…` import then resolves inside the
bundle. The CLI does this natively but needs `supabase login`, which it still
does not have.

### 5. Suggestion, not done: `geolocator` is installed and imported nowhere

§8 said GPS would arrive with Phase 4's map; Phase 4 shipped without it, so this
is an unfulfilled plan rather than a pending one, and `profiles.home_lat`/`home_lng`
are still written by nothing. An unused native dependency is precisely the
`flutter_image_compress` lesson — a package that broke the build while nothing
imported it.

**Left in place deliberately**, because CLAUDE.md says not to add a dependency
without asking and the symmetric courtesy is not to remove one either. Dropping it
is one line in `pubspec.yaml` plus `flutter pub get`; re-adding it later is the
same line.

### Phase 3's acceptance now passes — all three criteria

Deploying v6 was the whole blocker. **20 generations, 0 refused, cache hit
confirmed**, against 11 errors of 20 before.

**Read the "fresh" column, not just the pass.** The first re-run showed 20/20 —
but 15 were cache hits, because the entries from 2026-08-10 were still valid
(nothing had been re-imported, so `places_version` had not moved). "Zero invalid
IDs" across 15 replays of already-validated payloads is true and nearly vacuous:
invariant 2 was tested 5 times, not 20. So `plan_cache` was emptied and the run
repeated — **10 fresh generations then 10 cache hits**, which is the most the
harness can produce, since it cycles ten distinct constraint sets and runs 11–20
repeat 1–10's.

**Invariant 2 verified from outside the function under test.** The 20 runs
produced 58 plans and 162 stops referencing 14 distinct `place_id`s; all 14 were
checked against `places` directly — 14 exist, 14 are `curated`, **zero invented,
zero non-curated**. `cost_generated_plan`'s own `valid` flag was not the evidence.

**The third criterion is now a command**, not a note saying "do this by hand":
`node supabase/functions/generate-plan/verify-totals.mjs` recomputes every plan's
places, fares and total from `places` and `transit_fares`, taking only the stop
slug, the leg mode and the claimed totals from the payload. **58/58 on all three
figures.** It deliberately does the arithmetic in Node rather than SQL: a
recomputation in the same dialect, with the same joins, in the same engine can
repeat the original's mistake.

> **The first hand-check reported a mismatch that was the check's fault.** It
> summed every `transit_fares` row for a barangay pair and got ₱160 where the
> function said ₱60 — because **Poblacion↔Turo has both a tricycle row (₱25 pp)
> and a jeepney row (₱15 pp)**, and a leg picks one. Worth keeping as the failure
> mode of verification-by-recomputation: the check is code too.

**Two of twenty runs returned 2 plans instead of 3.** Not a criterion violation —
no plan was flagged invalid, so the model simply gave two where the prompt asked
for three. Prompt adherence, not an invented place. Recorded so nobody reads it as
a rejection.

**What is still not answered, and cannot be yet:** whether the plans are any
*good*. All 15 places are `test-*`, so 20 generations prove the pipeline and
nothing about a Bocaue Saturday. §8 already separates those two claims.

### Also fixed here

**Two migration filenames did not match the ledger.** `apply_migration` stamps its
own version, and Phase 6's append-only migration was committed as `…101500` while
the database recorded `…095956`. A later `supabase db push` would have tried to
replay it. Both renamed to match.

## UI direction session — what was built, and the six premises that were wrong

Nat reviewed mockups and brought twelve changes, split by him into buildable and
specs-only. **Six of the premises did not match the repository**, which moved two
items out of "buildable". Recorded because the same assumptions will otherwise
come back:

| Assumed | Actual |
|---|---|
| §13 (activities-first vs places) is open | There was no §13 — the doc ended at §12 and "activities-first" appeared nowhere in `docs/`. Confirmed by Nat as an unwritten decision, then **withdrawn 2026-08-18**. Now written up as `00-architecture.md` §13, recorded as withdrawn so it is not re-proposed |
| `places` has zero rows | 15, all `test-*` |
| nav "stays three tabs until Phase 7" | **Zero tabs.** No `NavigationBar` anywhere; home is a `Column` of buttons |
| starter chips are numbered | already unnumbered |
| profile screen needs no changes | **there is no profile screen** |
| preferences groups need expanding | **no preferences screen, and `profiles` has no columns for one** |

**Built: items 1, 4, 5.** Splash animation, starter-chip copy, budget sheet.

**Item 7 (resource catalogue) was NOT built, deliberately.** It is buildable in
the mechanical sense and was held because of what the catalogue turned out to
look like — see below. It needs the §13 call first.

**Everything else went into `02-design-system.md` §10, "Specified, not built"**,
including item 12 recorded as **cut** rather than dropped silently.

### The resource-catalogue finding, which is the reason item 7 is open

**18 of the 30 `resource_catalog` rows are required by no activity.** Orphans:
`tent`, `camping-gear`, `folding-chairs`, `cooler`, `flashlight`, `grill`,
`wrapping-paper`, `instant-camera`, `badminton-set`, `volleyball`, `yoga-mat`,
`playing-cards`, `books`, `gaming-console`, `bluetooth-speaker`, `projector`,
`motorcycle`, `car`.

`retrieve_activities` filters activities by `required_resource_ids`, so **a
resource no activity requires cannot change a single result.** It only lengthens
onboarding. Growing 30 → 50 unpaired would take the picker from 60% dead weight
to 76%.

So the useful version of item 7 is **resources paired with activities** — and
adding activities is the activities-first bet, which is exactly the decision §13
is supposed to hold. Pairing the existing 18 orphans is the cheapest real win in
the app and needs no new resources at all.

### Decisions taken

- **Item 6 (preferences) is spec-only at full scope**, Nat's call. Companion
  types beyond `Partner` are persona expansion (§11, and `CLAUDE.md`'s
  not-building list), so the picker cannot ship as a UI change.
- **Item 9: the activities-only price breakdown is not worth building.**
  Invariant 3 means a breakdown renders server output, so it cannot precede it;
  and omitting fares — ~12% of a Bocaue budget — teaches the wrong shape.
- **Item 12 (national map) recommended cut.** A 99%-empty map of the Philippines
  is a bare empty state promoted to a permanent nav slot, which the coverage
  rules forbid. Belongs on the Phase 9 site.

### Corrections worth not re-making

- **The budget is not per person.** The brief said any custom value "must still
  respect per-person division"; §9 is the reverse — *prices* are per person,
  totals multiply by `party_size`, and the user's budget means the whole outing.
  The sheet now says "For the whole date, not each." on the surface where the
  number is typed, with a test on the sentence.
- **Perplexity and Google Flights are web references** and §7 says mobile only.
  Both ship mobile apps. Noted in `docs/design/references/README.md`.
- **`docs/design/references/` did not exist** though §7 said it did. Created.
- **`02-design-system.md` §9's heading had lost its `##`**, so it was invisible
  to every outline and to `grep "^## "`. Fixed.

### Gotchas from this session

- **`pumpAndSettle` never returns on the splash** — the `CircularProgressIndicator`
  is indeterminate. Same trap as the intake's `LinearProgressIndicator`. Pump a
  fixed duration instead.
- **A `CurvedAnimation` built inside `build` leaks a parent listener every
  frame.** Hoist it to the `State` and dispose it alongside the controller.
- **`MediaQuery.disableAnimationsOf` is unavailable in `initState`.** The
  reduced-motion decision has to happen in `didChangeDependencies`, guarded so it
  runs once.
- **The splash animation is bound by interruption, not duration.** `AmoraApp`
  swaps it out the instant startup resolves, so it is cut off rather than played
  and must look deliberate at every frame. A minimum-duration hold would fix that
  and is forbidden — it delays startup, which is what `appStartupProvider` exists
  to avoid. Recorded as `02-design-system.md` §6's one sanctioned exception to
  "never animate for delight alone".

## Gate A — preferences. Built 2026-08-18.

Two migrations (`20260818121939`, `20260818121957`), one screen, one model file.
Spec is `02-design-system.md` §10.2, now marked BUILT rather than specified.

**`profiles` gained `companion_type`, `interests text[]`, `usual_budget_php_cents`.**
RLS untouched — `profiles_select_own` / `profiles_update_own` filter on the
primary key, and adding columns does not widen a policy that does that.

**Companion type stores five values and offers one.** The check constraint
permits `partner|friends|family|solo|group` so widening the persona is later a
change to `CompanionType.offered` rather than a migration (§11). Only `partner`
is selectable, because offering the rest *is* shipping friends and families
whatever retrieval does with the value. **There is a test asserting the other
four are absent** — that test is the thing between "storage is ready" and "the
feature shipped by accident".

**Interests are `activities.category` slugs, and there are seven, not the twelve
first specified.** Ranking happens on `category`, so an interest matching no
category could not change a single result — Photography, Films, Shopping, Faith,
Learning and Just-walking-around were all exactly that. **Same defect as the 18
orphan resources, one week apart**, which is why it was caught. Finer interests
need an `activities.tags` column to rank against; that is a real feature, not a
relabelling.

**`retrieve_activities` ranks and never filters.** Verified against the live
database in four directions before the Dart went in: no interests → 33 rows,
`music` only → 33, every category → 33, a bogus slug → 33, and the music rows
sort first. Two-argument callers (`build_simple_plan`, `cost_generated_plan`, the
`generate-plan` Edge Function) still resolve through the default and were not
touched.

**The saved budget seeds the sheet, not the constraint.** Writing it into
`IntakeConstraints` would be an inferred value applied silently (§8) *and* would
suppress the starter chips, since those only render while nothing is
established. `_askBudget` passes it as the sheet's opening value instead.

**Reachable from home, temporarily.** "How you usually plan" sits below the four
buttons that do the job — preferences change ordering, never whether the app
works, so they must not read as a setup step. It moves under Profile at Gate B.

**Gotchas:**

- **`ideas_test.dart` broke the moment Ideas read the profile.** It had no
  `profilesRepositoryProvider` override, so `currentProfileProvider` reached a
  real Supabase client and every activity assertion failed with an empty list.
  Any screen that starts reading the profile needs both that override and
  `authRepositoryProvider`.
- **The preferences screen has three sections and a widget-test viewport is
  800 px.** The budget chips did not exist to tap. Raise
  `tester.view.physicalSize` — same fix and same reason as `add_stop_screen` and
  the Phase 6 sheet. Scrolling drags across the chips and starts a gesture.
- **`{for (final x in ?maybeNull) ...}` does not parse.** The null-aware element
  marker works on the *element*, not on the iterable of a `for-in`.

138 tests (up from 128), analyze clean, advisors show nothing new. **Not verified
on the phone** — that pass now owes the splash, the budget sheet and this screen.

## Review pass, post-Phase-3 — what it found

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

~~**Do not start Phase 3 until real data is in.**~~ **Overridden 2026-08-08** —
Nat chose to build every remaining phase first. Struck rather than deleted,
because it was the right call when written and the reasoning above it still is.

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

**Dependency flagged, then added 2026-08-08** — `youtube_player_iframe` 6.0.2.
The Kotlin Gradle Plugin check this line demanded was run and passed; the
`url_launcher` fallback was kept. See "The DIY tutorial player" above.

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

- **No credentials in documentation. Ever, including throwaway ones.**
  `HANDOFF.md` carried a test account's password from 2026-08-08 until
  2026-08-10, when GitGuardian flagged it on PR #4. **This repository is
  public.** No real key was ever exposed — `.env` has never been tracked and no
  JWT or API key literal exists anywhere in history — but the account was
  usable, and email confirmation is OFF, so anyone could have signed in and
  spent the Gemini quota that D7 depends on being free.
  - The password was **rotated**, not scrubbed from history: once changed, the
    historical copy is worthless, and rewriting a public repo with merged PRs to
    bury a dead dev credential costs every clone for no security gain.
  - Write **how to reset** a credential, never what it is.
  - **Email confirmation being OFF is what turns a leaked password into an
    account.** It is already on the pre-users list; this is a reason it is
    there, not a new task.
- **₱0, no credit card.** Already ruled out: Google Maps (billing account),
  Cloudflare R2 (card), and Supabase leaked-password protection (Pro Plan — the
  security advisor flags it permanently; do not chase it).
- **Never invent local data.** No places, prices, fares, opening hours, or
  tutorial URLs from model knowledge. Ever. The curated database is the whole
  business (D3). Blank templates and obviously-fake `EXAMPLE` rows are fine;
  plausible-looking invented rows are not.
- **Claude commits and pushes.** Standing authority, granted 2026-08-08. One
  clean commit per phase on a branch off `master`, pushed, SHA reported. This
  **reverses** the previous rule ("print the messages and stop"); it is written
  here rather than argued again.
- Commits carry no Claude attribution — `.claude/settings.json` sets
  `includeCoAuthoredBy: false`.

## The working loop, from 2026-08-08

Agreed with Nat and now the standing shape of a session:

1. **Plan the phase**, get approval, build it.
2. **Review the whole codebase** — not just the diff. `flutter analyze`,
   `flutter test`, `npx deno@latest test supabase/functions/generate-plan/`, and
   Supabase `get_advisors` for both `security` and `performance`.
3. **Fix what that finds**, in the same commit.
4. **Update the docs in the same commit**, never after — `HANDOFF.md` and any
   `00-architecture.md` phase entry the work changed.
5. **Commit, push, open a PR, merge it.** One commit per phase on a branch off
   `master`, then `gh pr create` and `gh pr merge --merge` — a merge commit, so
   the branch stays visible in the network graph. Then **stop** and plan the
   next phase.

**GitHub CLI** was installed 2026-08-08 via `winget install GitHub.cli`. It is
not on PATH in an already-open shell; use
`"C:\Program Files\GitHub CLI\gh.exe"` or open a new terminal. **`gh auth login`
is interactive and Nat has to run it** — Claude cannot.

**Known-permanent advisor noise, so a future session does not chase it:**
`plan_cache` **and `intake_cache`** RLS-with-no-policies (that *is* "service role
only" — both are server infrastructure, not user data), leaked-password
protection (Pro-only, D7), and six `unused_index` INFO notices. The indexes are
not dead — `plans` and `plan_items` sit at **zero rows** between test runs, and
Postgres will not choose an index on a 15-row table, so "never used" measures the
dataset, not the schema. Re-check once real data and real traffic exist.

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

### The Google Form — decided 2026-08-12, and what it can and cannot produce

Nat intends to collect leads by **asking friends about their own dating
experiences via a Google Form**, then converting the answers to a readable
format, once every phase is built. That time has now arrived.

**Form answers are candidates, never rows.** They go in
`supabase/seed/candidates/`, whose columns are deliberately incompatible with
`places.csv` — pasting them across exits 1 on `assertHeaders`, which is the
guard. §10.4: a candidate is promoted **by a visit or by a phone call**, and a
resident's own knowledge counts only for facts that do not move. "It was around
₱200 last month" cannot be dated honestly, and a price is exactly the fact whose
staleness breaks a promise in public.

**It is nonetheless the best candidate source available**, and better than web
search on the axis that matters: search agreement measures who copied whom, while
a friend who went there is first-hand. It should be sized accordingly — a wide
form to a dozen friends is a morning's work and could produce more real leads
than the whole candidates folder currently holds.

**What it can fill directly is `place_notes`.** A note is a dated subjective
observation carrying a `source_label`, not a decaying fact — "no lift to the
second floor", "gets loud after 8pm", "the corner table is the good one". That is
precisely what a phone call cannot reach (see the note above), and it is the layer
D2 leans on to replace the Reddit tab. **Ask for these explicitly**; they are the
form's highest-value output, not a by-product.

Practical shape, so the conversion is not painful: ask for one place per response,
with the barangay, roughly what two people spent, when they last went, and one
sentence of what it is actually like. The first three become a candidate row to
phone; the last becomes a `place_note` once the place is curated.

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

**Real:** `resource_catalog` (31 rows) and `transit_fares` (15 real barangay
routes — Poblacion, Turo, Bunlo, Lolomboy, Duhat, Wakas, Batia, plus Marilao and
Balagtas). `activities` (33) are generic and fine.

> **The catalogue was re-shaped on 2026-08-18, not grown.** 18 of the 30
> resources were required by no activity, and `retrieve_activities` filters by
> `required_resource_ids <@ p_owned_resource_ids` — so **a resource no activity
> requires cannot change a single result.** It only lengthened onboarding.
>
> 15 orphans were paired to one new activity each; `camping-gear` was retired as
> a duplicate of `tent` (zero owners, so nothing cascaded); and two resources were
> added because pairing revealed real gaps — `videoke-machine` and `guitar`.
>
> **`car` and `motorcycle` are still orphaned, deliberately.** They belong to the
> **legs** layer, not the activities layer: someone with a car should not be
> quoted a tricycle fare. Inventing "Sunset ride" would have paired the rows and
> left the real modelling error in place. Making `fare_for` aware of owned
> transport is its own change and touches money, so invariant 3 makes it a server
> change rather than a seed one.
>
> Verified in both directions after applying: owning nothing returns **6**
> activities (those requiring none), owning everything returns **33**, and owning
> only `projector` returns **7** — exactly one unlocked. A `guitar` owner sees
> "Learn a song together" and *not* "Videoke night", so containment is not
> over-broad.
>
> **Design rule for any future pairing: require only the resource the activity is
> impossible without.** Every listed resource must be owned, so requiring a
> nice-to-have silently hides the activity.

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
