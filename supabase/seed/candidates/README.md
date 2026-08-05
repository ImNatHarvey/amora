# Candidates — research aid, not data

This directory holds **places we have heard about and not yet verified.** Nothing
here is data. Nothing here may be imported.

Full reasoning: `docs/00-architecture.md` §10.4. The short version is that search
agreement measures *copying*, not truth — a Facebook page, an aggregator, a blog
and a Reddit comment usually trace to one stale origin, and a model's confidence
is that same signal counted twice. Search is reasonable evidence for **identity**
(the name, the street, that it existed) and near-worthless for **volatility**
(hours, price, still open). Volatility is what Amora sells.

## What search is allowed to do

Produce a list of leads worth walking to. That is genuinely useful — knowing which
six cafés exist saves an afternoon of wandering.

## What search may never do

Fill in `places.csv`. A row there asserts that someone stood at the door.

## Why you cannot accidentally import this

`candidates.csv` is **deliberately shaped so it cannot become `places.csv`.** It
carries `source_url` and `claimed_hours`; it carries no `slug`, `lat`, `lng`,
`barangay` or `opening_hours`.

`csv_to_sql.mjs` validates headers exactly — it refuses both unknown and missing
columns and aborts before emitting any SQL. So pasting candidate rows into
`places.csv` fails loudly rather than seeding plausible fiction.

That is the guard: a mechanism, not a habit. And note that the columns retrieval
actually needs are precisely the ones a search cannot supply — coordinates taken
at the door, a verified barangay, hours someone read off the sign.

## Columns

| Column | Meaning |
|---|---|
| `name` | As the source spells it. Expect this to be wrong on the signage. |
| `area_guess` | Rough area. **Not** a barangay — that gets confirmed in person. |
| `source_url` | Where the claim came from. One row per place, best source. |
| `source_type` | `facebook` · `reddit` · `youtube` · `blog` · `maps` · `word-of-mouth` |
| `claimed_hours` | Free text, as claimed. Never the `opening_hours` grammar — that would invite a copy-paste. |
| `claimed_price_php` | Free text. "around 150-200" is fine and honest here. |
| `last_seen_online` | Date of the most recent post/review found. **The staleness signal** — an 18-month-old last post is the strongest hint a place has closed. |
| `status` | `unvisited` · `visited-confirmed` · `visited-rejected` · `closed` |
| `notes` | Anything useful for the visit. "2nd floor", "ask about the back room". |

## Promotion — the two paths into the catalogue

A candidate is promoted by **a visit or a phone call**, never by more sources
agreeing. Both establish the volatile facts from the party that sets them; the
difference is what else you learn while you are there.

**By visit**

1. Walk there.
2. Confirm it exists, is open, and read the prices off the menu.
3. Set `status` to `visited-confirmed`.
4. **Type the row into `places.csv` by hand**, using
   `supabase/seed/FIELD-CHECKLIST.md` for field order and the mandatory columns.
   Coordinates come from your phone at the door — never from the source.
5. Set `verified_on` to the date you were actually there, and `verified_method`
   to `visited`.

**By phone** — see `supabase/seed/DESK-CHECKLIST.md` for the call itself.

1. Find the number. A phone number is **identity**, which is what search is
   actually good for — so `source_url` earning you a number is this file working
   as intended.
2. Call. Establish the hours and the current price of the cheapest realistic
   order, from the person who sets them.
3. Set `status` to `visited-confirmed` — the name is now slightly wrong, and it
   stays rather than churn the column; `verified_method` carries the distinction.
4. Type the row by hand as above. **Coordinates still may not come from the
   source** — use OpenStreetMap, which is identity data, or leave the row for a
   day you are passing.
5. Set `verified_on` to the date of the call, and `verified_method` to `phoned`.

A phoned row is a real row, and it is thinner than a seen one: nobody describes
their own second floor as having no lift. `place_notes` mostly waits for a visit.

A `visited-rejected` or `closed` candidate stays in this file. Knowing a lead was
checked and failed is worth as much as knowing one succeeded — it stops the same
café being researched three times.

## Word of mouth belongs here too

A friend saying "there's a good place near the plaza" is a candidate, not a row.
Same rules, `source_type: word-of-mouth`. Trusted people are still not a substitute
for standing at the door, because they are usually reporting a visit from months
ago.
