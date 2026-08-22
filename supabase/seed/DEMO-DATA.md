# Demo data

**These 15 places are generated. Nobody visited them, phoned them, or remembered
them. Every price and every opening time in this set is invented.**

They exist so the app can be held and used on a phone before
`DESK-CHECKLIST.md` has been run. They are not the catalogue, they are not
evidence for any acceptance criterion, and they are not to be distributed.

## What makes them safe

| Guard | Where |
|---|---|
| `verified_method = 'generated'` on every row | `places` check constraint, migration `20260822120827` |
| `verified_on` is null — no date anybody checked | the rows themselves |
| `demo-` slug prefix on every row | `places.csv` |
| The prefix and the method must agree, both ways | `csv_to_sql.mjs`, negative-tested |
| One command removes all of it | `wipe-demo.sql` |
| Phase 0 and Phase 2 stay open in the ledger | `docs/HANDOFF.md` |

**`verification_tier` is still `curated`, and that is correct.** That column
answers *did a user submit this row* — its two values are `curated` and
`user_submitted`, and `= 'curated'` is filtered at eight sites including
`places_read` RLS, `retrieve_candidates`, `build_simple_plan` and
`places_version()`. Widening it would weaken the guard that keeps one bad user
row out of every other user's results, which is invariant 5's whole mechanism.
These rows were entered by the owner, so `curated` is the truthful answer to the
question that column asks. The question with the uncomfortable answer is *how
were these facts established*, and that is `verified_method` — which
`docs/00-architecture.md` §10.4a created for exactly this.

## The uncomfortable part

Some of these are **real, named businesses with invented prices and hours**.
Cafe Galilea is in `candidates/candidates.csv` as unvisited. St. Martin of Tours
Parish and the Kim Taegon Shrine are real places. §10.4 forbids this in the
curated catalogue, and it is forbidden here too — what makes this permissible is
that the rows are marked, removable, and never leave one phone.

**If this build reaches anyone Nat did not hand it to, that is the coverage gate
in `HANDOFF.md` being crossed, and these rows must be wiped first.**

## What they were derived from

Nat supplied names, barangays, coordinates, hours, a per-couple budget and a
one-line vibe for each. Conversion into the schema:

- **Prices were halved.** The supplied figure reads as a per-couple date budget;
  `places.price_min_php_cents` is **per person** and totals multiply by
  `party_size` (§9). Entered raw, a ₱1,200 dinner would have cost the couple
  ₱2,400.
- **Categories** were mapped onto the existing vocabulary so
  `cost_line_for_place` files each one into the right breakdown line: `cafe`,
  `food`, `restaurant`, `market` → food; `vendor`, `florist` → gifts; everything
  else → activities.
- **Hours** were converted to the `is_open_at` grammar. Five of the fifteen are
  closed on some weekday, so "is it open" is a question with a real answer.
- **The vibe lines** became `notes` and `place_notes`.

## The fares

66 rows, one per unordered barangay pair across the 11 barangays plus each
barangay with itself — `fare_for` matches either direction, so one row per pair
is enough. Bucketed by straight-line distance between barangay centroids, using
the four route classes Nat gave:

| Distance between centroids | Class | Fare | `is_per_person` |
|---|---|---|---|
| same barangay | intra | ₱15 | true |
| under 1.2 km | adjacent | ₱20 | true |
| 1.2–2.1 km | cross-highway | ₱30 | true |
| over 2.1 km | deep transit, special trip | ₱100 | **false** |

The 2.1 km threshold is set so Poblacion → Igulot and Poblacion → Wakas land in
the special-trip class, which is the example Nat gave. It matters that the class
exists at all: `is_per_person = false` is the one fare branch that distinguishes
a vehicle hired once from a seat bought twice, and without it nothing in the
seed exercises it.

## Verified after seeding

Positive assertions, not counts that zero would satisfy:

- ₱0 from Poblacion → **2 stops**, total ₱0.
- ₱400 from Poblacion → **3 stops**, total ₱250, all of it on the food line.
- Fare legs fire from Lolomboy, Taal, Tambobong and Wakas — ₱40–₱80 per plan,
  crossing 2–3 barangays each. Poblacion alone produces none, correctly: every
  leg there is under the 800 m walk threshold.
- `fare_for` on all six branches: per-person scales with party size, the special
  trip does not, under 800 m is free, and an unknown pair reports
  `fare_known = false` rather than ₱0.
