# Field checklist

For collecting real Bocaue data on foot. One place at a time, in the order you
can actually observe things while standing there. Type into a notes app; the
CSVs get filled in at a desk afterwards.

Formats and the full grammar live in `README.md`. This file is the field copy.

**Target: 15 places.** Read **"Spread"** before deciding where to go — *where*
they are matters as much as how many, and getting it wrong means no fare is ever
exercised by a real plan.

On this page: the three silent breakers · per place · where leads come from ·
per fare ride (incl. the **riding list**) · DIY tutorial videos · spread ·
at the desk afterwards.

---

## ⚠️ The three columns that break things silently

None of these errors out. They just make a row quietly wrong or absent, and you
will not notice until you are back at the desk wondering where something went.

1. **Blank `barangay` → the place can be retrieved but never costed.** Every leg
   touching it reads "fare not recorded", because barangay is the only key fares
   have.
2. **Blank `opening_hours` → the place is never retrieved at all.** Retrieval
   promises "currently open", and unverified hours cannot support that promise.
3. **Wrong `is_per_person` on a fare → every plan using that route is out by
   2×**, in whichever direction. A jeepney is `true`, a tricycle special trip is
   `false`, and nothing about the number itself reveals which you meant.

If you cannot verify a place's barangay *and* hours, **leave it out of the CSV
entirely** and come back to it. A missing row is a known gap; a half-filled row is
a silent one.

---

## Per place

**1. Name** — exactly as the signage reads. Not how Google spells it.

**2. Category** — one word, reused across places: `cafe` `restaurant` `food`
`park` `plaza` `viewpoint` `market` `landmark` `sports` `florist` `vendor`.

**3. Barangay** ⚠️ **Never leave blank.**
This is load-bearing, not a label. It is the only key fares have, and it is what
the origin picker builds a coordinate from. A place with a blank barangay can be
retrieved but never costed, and it drags every leg touching it into "fare not
recorded".

**4. Address** — street or landmark. Quote it in the CSV if it contains a comma.

**5. Coordinates** — take them standing at the door, from your phone's GPS.
Six decimal places. `14.798100, 120.924700`.

**6. Opening hours** ⚠️ **Never leave blank.**
A place with no recorded hours is **never returned by retrieval** — deliberately,
because "currently open" cannot be promised about hours nobody checked. A place
you could not verify is better left out of the CSV entirely than added with this
empty.

- Grammar: `mon-sun 10:00-22:00`, `mon-fri 09:00-22:00; sat-sun 08:00-23:00`
- **Omit closed days.** A day never mentioned is closed.
- **Closes after midnight?** Write it against the day it *opens*:
  `fri-sat 18:00-02:00` is Friday and Saturday evening, each into the small
  hours. Never write `sat 00:00-02:00`. These rows are now fully supported and
  they are the ones an evening-planning app most needs — record them.
- All day is `24h`. Never `10:00-10:00`, which is rejected as ambiguous.

**7. Price min / max, in pesos** — not centavos. `180` or `180.50`.
⚠️ **Per person, always.** One person's spend, never a couple's.
- **min** = the cheapest *one person* can realistically do something here. One
  drink, one serving. A park is `0`, and zero is a real answer, not a missing one.
- **max** = a normal upper spend for one person, not the priciest thing on the menu.
- The app multiplies by party size, so entering a couple's total here would double
  every plan. If you catch yourself thinking "about ₱400 for the two of us",
  write `200`.
- Read them off the actual menu or price list. Photograph it.

**8. Indoor?** `true` / `false` — has a roof and walls. Matters for rain.

**9. Sunset facing?** `true` / `false` — only `true` if you can actually see the
sunset from where people sit.

**10. Contact + social** — mobile number, Facebook page URL. Blank is fine.

**11. Notes** — the lived-experience layer, the reason someone would trust this
over a map pin. "Second floor, no lift." "Empty before 4pm." "Aircon only in the
back room." Quote it if it contains a comma.

**12. Date you were there** — goes in `verified_on`. This is what makes a
staleness policy possible later: a row verified in August 2026 and a row verified
last week are not equally trustworthy, and without the date nothing can tell them
apart.

**Slug** is derived later at the desk (`corner-cafe`), not in the field.
Never start one with `EXAMPLE` — the importer skips those.

---

## Where leads come from

If you researched a place online first, it belongs in
`supabase/seed/candidates/candidates.csv` **until you have stood at the door** —
see that directory's README. Search is good for finding what exists and useless
for hours and prices, so a candidate saves you an afternoon of wandering and
nothing more. Coordinates always come from your phone at the door, never from the
source.

---

## Per fare ride ⚠️ the gap that matters most

Currently **no intra-barangay fares exist at all**, so any two places in the same
barangay more than 800 m apart read "fare not recorded". In a walkable town that
is the most common leg the app generates, which makes this the highest-value
data on this page.

Record `from_area`, `to_area`, `mode` (`tricycle` / `jeepney`), `fare_php`,
`is_per_person`, and the date you rode it.

⚠️ **`is_per_person` is the one that will trip you up.** A jeepney charges every
passenger, so `true` — record what *one* person pays. A tricycle special trip is
one fare for the whole vehicle no matter who is in it, so `false` — record the
whole fare. Getting this backwards doubles or halves every plan that uses the
route, silently.

If a tricycle route has both a regular per-passenger rate and a special-trip rate,
**record the one a couple would actually pay**, set `is_per_person` to match *that*
rate, and note the other in the notes.

### New routes to collect

- **One row per barangay for itself** — `Poblacion, Poblacion, tricycle, ...`.
  Same-barangay rows are legal and already resolve; nothing needs changing.
- **Also note how far you rode.** Not a database column — it settles a design
  question. If a 900 m hop and a 2.5 km hop inside one barangay cost the same,
  a flat row per barangay is correct permanently. If they differ, the fare model
  needs distance bands and we should talk before you collect more.
- If the TODA terminal has a **posted tariff board, photograph it.** A published
  local rate is curated data and may cover every short leg in one go.
- Legs under 800 m are computed as a free walk and never looked up — don't
  bother riding those.

### ⚠️ Riding list — 9 tricycle rows to confirm

These fares are real. **`is_per_person` on them is a guess.** The column was added
after they were collected and nobody recorded which rate was quoted, so all nine
default to `true`. Every one that was actually a *special trip* is currently
**doubling for a couple** in every plan that uses it.

For each: ride it with two people, and note whether the driver charged **once for
the trip** (`false`) or **per head** (`true`).

| | Route | Fare | Charged once, or per head? |
|---|---|---|---|
| ☐ | Poblacion → Turo | ₱25 | |
| ☐ | Poblacion → Bunlo | ₱30 | |
| ☐ | Poblacion → Wakas | ₱30 | |
| ☐ | Poblacion → Duhat | ₱35 | |
| ☐ | Poblacion → Lolomboy | ₱40 | |
| ☐ | Poblacion → Batia | ₱45 | |
| ☐ | Turo → Lolomboy | ₱30 | |
| ☐ | Turo → Bunlo | ₱35 | |
| ☐ | Bunlo → Lolomboy | ₱45 | |

Set `verified_at` at the same time — it is blank on all nine, so nothing currently
records that anyone has ridden them at all.

The **6 jeepney rows need no check**: a jeepney always charges per passenger.

**The fares themselves are correct and need no re-collection** — all six barangay
pairs among Poblacion, Turo, Bunlo and Lolomboy are already covered. The only
things missing on these nine rows are `is_per_person` and `verified_at`.

---

## Per DIY activity — tutorial videos ⚠️ check embedding at collection time

`activities.tutorial_url` is one hand-picked video per DIY activity, Tagalog
preferred. Phase 4 plays these **inside the app**, which adds a requirement that
is invisible if you only ever open the link normally:

- **Record the full YouTube URL**, not a shortened or shared-app link.
- **Verify the video allows embedding.** Some uploaders disable it. Such a video
  plays perfectly when you tap the link, and shows an error inside an in-app
  player — so a link that looks fine in the field fails months later at Phase 4.
- **How to check in ten seconds:** open the video on a desktop browser, right
  click, "Copy embed code". If YouTube offers it, embedding is allowed. On a
  phone, share → if "Embed" is absent and the uploader has restricted it, pick a
  different video.
- **Prefer a video that still works if embedding fails** — the app keeps an
  "open in YouTube" fallback, but a plan is better if the first choice just works.
- One good video beats three mediocre ones. This is curated data like everything
  else: if you would not send it to a friend, do not record it.

This only applies to activities marked `is_diy`. Leave `tutorial_url` blank for
everything else.

---

## Spread ⚠️ read before choosing where to go

Every placeholder place sits in Poblacion, which is why every generated leg is
currently a walk and the fare path is exercised only by SQL assertions, never by
a real plan.

The builder takes the **3 nearest affordable places** from your origin. If the
origin barangay alone holds 3+ places within 800 m of each other, every leg is a
walk and no fare is ever looked up.

**So, for the fare path to be genuinely exercised:**

- **At least 3 barangays**, and realistically 4.
- **No more than about 5 places in any one barangay** — concentration is what
  keeps legs short.
- Suggested split of the 15: **Poblacion 5, Turo 4, Bunlo 3, Lolomboy 3.**
  All six pairs among those four already have fare rows, so a plan crossing any
  of them costs out completely the day the data lands.
- Adjacent barangay centroids in Bocaue are comfortably over 800 m apart, so any
  cross-barangay leg will trigger a real fare lookup rather than a walk.

A barangay with no curated places cannot be a plan origin yet, even when fares to
it exist — there is no honest coordinate for it. That resolves itself as the
catalogue grows.

---

## At the desk afterwards

Fill the CSVs in this order, since later files reference earlier ones:
`places.csv` → `transit_fares.csv` → `place_notes.csv` (references place slugs)
→ `activities.csv` (only if you added tutorial URLs).

Then run the sequence below from `C:\Users\jharv\amora`. **The order matters:**
generate before deleting, so a validation failure costs you nothing.

```sh
# 1. Validate and generate FIRST.
#    The importer refuses on a bad header, a wrong field count, a duplicate key
#    or an unknown resource slug — it fails rather than corrupting. If it stops
#    here, nothing has been touched: fix the CSV and run it again.
node supabase/seed/csv_to_sql.mjs --out seed.sql
```

```sql
-- 2. Only once step 1 succeeds: clear the placeholders. Notes cascade.
delete from public.places where slug like 'test-%';
```

```
# 3. Apply seed.sql — execute_sql in a Claude Code session, or psql.
```

```sql
-- 4. Verify. The first three should read 15, 0, 0.
select count(*) as places     from public.places;
select count(*) as leftovers  from public.places where slug like 'test-%';
select count(*) as unusable   from public.places
  where barangay is null or opening_hours is null;

-- Spread: at least 3 barangays, none holding much more than 5.
select barangay, count(*) from public.places group by barangay order by 2 desc;

-- Every barangay that can now be a plan origin.
select * from public.origin_areas('Bocaue');

-- Barangay pairs with no fare in either direction: your next riding list.
with b as (select distinct barangay from public.places where barangay is not null)
select x.barangay, y.barangay from b x join b y on x.barangay < y.barangay
where not exists (
  select 1 from public.transit_fares f
  where (f.from_area = x.barangay and f.to_area = y.barangay)
     or (f.from_area = y.barangay and f.to_area = x.barangay));
```

5. `flutter run` on the device and build a plan from a real barangay — **once at
   ₱200 and once at ₱600.** Three real, currently-open places with costed legs
   **is Phase 2's acceptance criterion**, and that run is what closes the phase.

   Run both because ₱200 is the *couple's* budget, so retrieval only admits places
   at ₱100 a head. If ₱200 returns almost nothing but ₱600 works, retrieval is
   fine and you have learned something real about Bocaue's price floor. If ₱600
   returns nothing either, the problem is the data or the query. Two runs turn an
   ambiguous failure into a diagnosis.

Re-running the import after editing a row updates that row; it never duplicates.
Editing a price and re-importing is the normal way to correct data.
