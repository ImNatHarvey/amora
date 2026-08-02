# Field checklist

For collecting real Bocaue data on foot. One place at a time, in the order you
can actually observe things while standing there. Type into a notes app; the
CSVs get filled in at a desk afterwards.

Formats and the full grammar live in `README.md`. This file is the field copy.

**Target: 15 places.** See "Spread" at the bottom — *where* they are matters as
much as how many.

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
- **min** = the cheapest you can realistically do something here. One drink, one
  serving. A park is `0`, and zero is a real answer, not a missing one.
- **max** = a normal upper spend, not the most expensive thing on the menu.
- Read them off the actual menu or price list. Photograph it.

**8. Indoor?** `true` / `false` — has a roof and walls. Matters for rain.

**9. Sunset facing?** `true` / `false` — only `true` if you can actually see the
sunset from where people sit.

**10. Contact + social** — mobile number, Facebook page URL. Blank is fine.

**11. Notes** — the lived-experience layer, the reason someone would trust this
over a map pin. "Second floor, no lift." "Empty before 4pm." "Aircon only in the
back room." Quote it if it contains a comma.

**Slug** is derived later at the desk (`corner-cafe`), not in the field.
Never start one with `EXAMPLE` — the importer skips those.

---

## Per fare ride ⚠️ the gap that matters most

Currently **no intra-barangay fares exist at all**, so any two places in the same
barangay more than 800 m apart read "fare not recorded". In a walkable town that
is the most common leg the app generates, which makes this the highest-value
data on this page.

Record `from_area`, `to_area`, `mode` (`tricycle` / `jeepney`), `fare_php`, and
the date you rode it.

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

Existing inter-barangay rows already cover all six pairs among Poblacion, Turo,
Bunlo and Lolomboy. They need no re-collection, only `verified_at` once ridden.

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

1. Fill the CSVs in this order: `places.csv`, then `transit_fares.csv`, then
   `place_notes.csv` (it references place slugs).
2. Clear the stand-ins: `delete from public.places where slug like 'test-%';`
   (notes cascade).
3. `node supabase/seed/csv_to_sql.mjs --out seed.sql` — it refuses to run on a
   bad header, a row with the wrong field count, a duplicate key or an unknown
   resource slug, rather than corrupting data quietly.
4. Apply, then re-run the Phase 2 device check.
