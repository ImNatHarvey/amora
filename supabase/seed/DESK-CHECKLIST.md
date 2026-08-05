# Desk checklist

For building the catalogue **without leaving the house.** Two layers: places you
already know, and places you can phone. Formats and the full grammar live in
`README.md`; the doctrine is `docs/00-architecture.md` §10.4a. `FIELD-CHECKLIST.md`
is the copy you take out when a row genuinely needs a visit.

**Target: 8 places across at least 3 barangays.** Eight is a floor, not a quota.

On this page: what a desk may establish · layer 1, places you know · layer 2, the
phone call · what stays out of reach · spread · then the import.

---

## ⚠️ The one rule everything else follows from

**Identity may come from memory, a map, or a search. Volatility may come only from
standing there, a phone call, or a user report.**

| Fact | Class | May come from |
|---|---|---|
| The place exists, and its name | identity | memory, map, search |
| Barangay | identity | memory, map |
| Coordinates | identity | OpenStreetMap, or your phone at the door |
| Free / no price to be wrong about | stable | memory |
| Hours of a public plaza or park | stable | memory, LGU or parish publication |
| **A menu price** | **volatile** | **visit or phone call only** |
| **This week's opening hours of a business** | **volatile** | **visit or phone call only** |
| **Still trading at all** | **volatile** | **visit or phone call only** |

The test for whether a fact is stable is not how sure you feel. It is: **could this
have changed since you last looked, without anyone telling you?** If yes, it is
volatile, and your memory of it is a guess with a local accent.

---

## Layer 1 — places you already know

The free public layer, and the reason it works from a desk: it is the class with
almost no volatile facts in it.

**Qualifies:** plaza · park · riverside · church grounds · covered court ·
barangay hall grounds · public market · landmark · viewpoint.

**Does not qualify, no matter how well you know it:** café · restaurant ·
carinderia · milk tea shop · any place with a menu. Those are layer 2.

For each place:

**1. Name** — as the signage reads, not as Google spells it.

**2. Category** — one word, reused: `park` `plaza` `viewpoint` `market` `landmark`
`sports`.

**3. Barangay** ⚠️ never blank. It is the only key fares have, and a place with no
barangay can be retrieved but never costed.

**4. Coordinates from OpenStreetMap.** Find the place, right-click → "Show address"
or read the URL. Six decimals. **OSM coordinates only** — its hours and its prices
are the same stale copies the search argument rejects (§10.4).

**5. Opening hours** ⚠️ never blank, or the place is never retrieved at all.
- Genuinely always open: `mon-sun 24h`.
- Daylight only, and you know it: `mon-sun 05:00-21:00`.
- **If you are not sure, do not guess a closing time.** Either leave the place out
  and come back to it, or walk past once and read the gate.

**6. Price** — `0` and `0`. If it has a gate fee you are not certain of today, it is
not a layer 1 row.

**7. Indoor / sunset facing** — `true` only if you can actually picture it.

**8. Notes** — this is where a resident beats every other source alive. "Dead before
4pm." "No shade at all." "Lights come on around 6." "Gets loud when there's a game."
A stranger cannot learn this and a phone call cannot ask for it.

**9. `verified_on`** — the date you were **last actually there**. Honestly. Not
today's date because you are typing today. If that date is two years ago, the row is
still fine for a plaza and you have just recorded something true about how much to
trust it.

**10. `verified_method`** — `resident`.

---

## Layer 2 — the phone call

This is how a priced place becomes a row without a visit. §10.4a: a call establishes
the volatile facts from the party who sets them.

**Finding the number.** A phone number is *identity*, which is what search is
actually good for. Put the lead in `candidates/candidates.csv` with its `source_url`
first — that file is the front end to this call, not a detour around it.

**The call, in about ninety seconds:**

> "Hi, good afternoon — are you open this Saturday evening? … Until what time? …
> And how much is a [milk tea / rice meal / the cheapest thing on the menu], more
> or less? … Thank you!"

Three questions. You are establishing:

1. **Open on the day and time Amora plans for** — an evening, a weekend.
2. **Closing time**, in the `opening_hours` grammar, written down while still on the
   call.
3. **`price_min`** — the cheapest one person can realistically spend. ⚠️ **Per
   person.** If they quote you a couple's total, halve it before it goes in the CSV.

**Then:**
- `price_max` — a normal upper spend for one person. If you did not ask, leave it
  blank rather than inventing a ceiling.
- Coordinates — **still not from the source.** OpenStreetMap, or leave the row until
  a day you are passing.
- `verified_on` — the date of the call. `verified_method` — `phoned`.
- Set the candidate's `status` to `visited-confirmed`.

**If nobody answers, the row does not exist yet.** An unanswered call is not weak
evidence of anything; it is no evidence. Try again another day, or leave it.

---

## What a phone call cannot reach

Worth knowing before you decide the whole catalogue can be built this way. A call
gets you hours and a price. It does not get you:

- that the seating is upstairs and there is no lift
- that it is empty before 4pm, or unbearable at noon
- that the aircon only reaches the back room
- that the photos are five years old

That is `place_notes`, the layer D2 says replaces the Reddit tab, and it mostly
waits for a visit. **A phoned row is a real row and a thinner one.** Ship it, and
fill the notes in the day you happen to be there.

---

## Spread ⚠️ decide this before typing, not after

The builder takes the **3 nearest affordable** places from the origin. So if the
origin barangay alone holds 3 places within 800 m of each other, every leg is a walk
and **no fare is ever looked up** — the fare data stays untested by any real plan.

- **At least 3 barangays**, realistically 4.
- **At least one barangay holding no more than 2 places.** That is what forces a
  third stop across a boundary and guarantees a real `fare_for` lookup. Start the
  acceptance run from that barangay.
- Poblacion, Turo, Bunlo and Lolomboy already have fare rows for **all six pairs**
  among them, so any leg between those four costs out completely on day one.
- Adjacent barangay centroids in Bocaue are comfortably over 800 m apart, so a
  cross-barangay leg triggers a real fare lookup rather than a walk.

A barangay with no curated places cannot be a plan origin, even when fares to it
exist — there is no honest coordinate for it.

---

## Then the import

The sequence, the validation queries and the acceptance runs are shared with the
field copy: **`FIELD-CHECKLIST.md` → "At the desk afterwards".** Follow it from
there. The only thing to carry across is that step 0 applies to layer 1 and layer 2
rows identically — clear the `test-*` rows out of the CSVs before you generate.
