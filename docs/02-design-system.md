# Amora — Design System

Status: v1 · Companion to `docs/00-architecture.md` · Save as `docs/02-design-system.md`

This file is authoritative for anything visual. If a widget disagrees with this
document, the widget is wrong.

---

## 1. Brand direction

Amora helps people make good memories on a small budget. The interface should feel
**warm, calm, and practical** — like a friend who knows the area, not a lifestyle
magazine.

**What we are:** warm, grounded, generous, quietly confident, local.
**What we are not:** a dating app, a luxury travel brand, a coupon site, a social feed.

Three consequences:

- **No romance clichés.** The palette leans rose because the MVP is for couples
  (see §2), and that is where it stops: no hearts, no floral motifs, no cursive
  script, no pink gradients. The colour comes from the seed and from users' photos,
  never from decoration.
- **Money is stated plainly, never apologised for.** ₱0 is displayed as confidently
  as ₱1,000. "Free" is a feature, not a limitation — never grey it out or shrink it.
- **Photos are the hero.** Most colour on screen will come from user photos of parks,
  food, and sunsets. The chrome stays quiet so the photos carry the warmth.

---

## 2. Colour

**Seed: `#B4436C`** — deep rose.

The MVP is scoped to couples planning a date, so a rose register is intentional
rather than something to design around. The specific hue leans pink-magenta, not
red: that keeps it clearly distinct from `error`, which stays reserved for errors
and must never read as decoration (see the rules below). It also holds up against
the greens and browns of outdoor photography, which is where most of the colour on
screen actually comes from.

> **This justification has a shelf life.** "Because the users are couples" stops
> being a reason the moment friends and families arrive (`00-architecture.md`
> §11). The colour itself is fine and should stay — deep rose is warm and
> grounded, which is the brief regardless of who is planning. But the *reason*
> needs restating as a brand choice before the persona widens, or the first person
> to read this after Phase 7 will correctly conclude the palette is now wrong and
> propose a redesign nobody needs.

> **Resolved — primary and error used to converge in dark mode.** Material 3
> lightens both roles for the dark scheme and they ended up neighbours:
> `primary #FFB1C6` against `error #FFB4AB`, ~27/255 apart on one channel.
> Verified on device, and "over budget" read as a decorative accent.
>
> **Both remedies were taken, because they fix different halves of the problem.**
> The dark scheme's error family is overridden to the Material tonal steps
> (80/20/30/90) of an orange-red hue, and the over-budget state carries an icon as
> well as a colour.
>
> The separation is a *hue* one, not a lightness one, and that is the point: at the
> same tone the two roles are equally light by construction, so error now runs
> green-over-blue (`#FFB68F`) where primary runs blue-over-green (`#FFB1C6`). The
> old red sat almost neutral between them, which is exactly why it disappeared.
>
> **Light mode is untouched** — `primary #8C4A5F` against `error #BA1A1A` was never
> the problem, and a user only sees one mode.
>
> Hue separation makes the colour legible; it does not make colour *sufficient*.
> Red-green colourblindness affects roughly one man in twelve and no hue choice
> fixes it, which is why the icon below is mandatory rather than advisory.
> Regression-tested in `test/theme_test.dart`, which asserts the relationship
> rather than the hex, so retuning the palette stays allowed.

**Generation:** the full Material 3 tonal range is derived at runtime by
`ColorScheme.fromSeed` in `lib/theme/app_theme.dart` — the same algorithm the
Material Theme Builder runs, with no generated file to keep in sync. Changing the
brand colour means changing one constant, `AppTheme.seedColor`.

### Rules

- **Always use `ColorScheme` roles.** `colorScheme.primary`, `.surface`,
  `.onSurfaceVariant`, and so on. Never a raw `Color(0xFF...)` in a widget.
- **Both modes are mandatory.** Every screen must be checked in light and dark before
  its phase is accepted.
- **Semantic colours are reserved.** Red means error, never decoration. Green means
  success or a confirmed saving, never a generic accent.
- **Never ship the default purple.** It is the signature of an untouched template.

### Budget colour semantics

Money needs consistent meaning across the app:

| Meaning | Role |
|---|---|
| Free / ₱0 | `tertiary` — treated as good news, never muted |
| Normal cost | `onSurface` |
| Over budget | `error` **and** `tokens.costOverBudgetIcon` — never colour alone |
| Partner / sponsored place | no colour treatment; a small text label only |

**Over budget must never be carried by colour alone.** It is the one money meaning
in this app a user cannot afford to miss, and one man in twelve cannot reliably see
it. The icon is part of the token set (`AmoraTokens.costOverBudgetIcon`) rather than
something each screen remembers, for the same reason the candidate CSV's columns are
incompatible by design: a mechanism beats a habit.

**"Free" is for prices, not for addends.** ₱0 reads as "free" wherever it is the
price of something — a place, a leg, a plan total. It reads as `₱0` wherever it is
one line of a breakdown or a constraint echoed back, because "places ₱200 · fares
free" describes a category rather than an amount. Learned on device; enforced by
tests in `plan_request_test.dart`.

**Money is per person; totals are for the party.** A price shown against a place
is what one person spends. A total is what the outing costs. Never show a
per-person figure where a user expects the total — the budget they typed meant the
whole date (`00-architecture.md` §9).

### Provenance of a price

From Phase 6b a price may be community-corrected, and the user must be able to
tell which they are looking at:

| Source | Label |
|---|---|
| Hand-verified seed | `₱180 · verified` |
| Community-corrected | `₱180 · reported by 4 people` |

No colour treatment for either — this is information, not a warning. Hiding the
difference would make the catalogue's weakest rows look identical to its
strongest, which is the one thing the whole verification model exists to prevent.

That last row matters. A sponsored place must never be visually louder than an
organic one. See invariant 4 in `CLAUDE.md`.

---

## 3. Typography

Material 3 `TextTheme`, default type scale, system font. No custom font in the MVP —
it costs bundle size and load time for negligible gain on low-end Android.

- Screen title: `headlineSmall`
- Section header: `titleMedium`
- Body: `bodyLarge`
- Supporting / captions: `bodyMedium` with `onSurfaceVariant`
- Peso amounts: `titleMedium`, tabular where aligned in a column

**Never set `fontSize` directly.** Use `Theme.of(context).textTheme.*`.

Sentence case everywhere. No ALL CAPS labels, no Title Case buttons.

---

## 4. Spacing and shape

A 4pt base scale, exposed as a `ThemeExtension` so it is tokenised rather than
scattered as magic numbers.

```
xs   4      sm   8      md  16      lg  24      xl  32      xxl 48
```

- Screen edge padding: `md` (16)
- Between cards in a list: `sm` (8)
- Between sections: `lg` (24)
- Inside a card: `md` (16)

**Radius**

```
small  8   — chips, text fields
medium 12  — cards, list tiles
large  20  — bottom sheets, dialogs
full       — FAB, avatars, mode pills
```

**Elevation:** flat by default. Use `surfaceContainerHighest` for raised surfaces
rather than shadows. Shadow only on the FAB and on bottom sheets.

---

## 5. Component rules

**Plan card** (the most important component in the app)
Cover photo, plan title, total cost as a prominent figure, duration, stop count.
Cost is never buried in body text. Free plans lead with "Free" in `tertiary`.

**Stop tile**
Numbered circle matching the map marker, place name, time, cost, thumbnail.
The number is the link between map and timeline — same number, same colour, always.

**Leg row**
Mode icon, distance or duration, fare. Walking legs show "Free", not a blank or a
dash. Dashed divider for walking, solid for paid transit — mirrors the map exactly.

> **Do not bake "exactly one mode per leg" into this component's API.** Render a
> leg from a list of segments that today always has length one. A day trip out of
> Bocaue is a bus, then an MRT ride, then a jeep — three fares in one leg — and
> that arrives as an additive `plan_leg_segments` table (`00-architecture.md`
> §12.3). Taking the list now costs nothing and saves rewriting the component
> later; assuming a single mode is the one decision here that would be expensive
> to undo.

**Budget input**
Large, centred, unmissable. This is the primary input of the entire product and
should feel like the main event on its screen, not a form field.

> Intake became conversational (`00-architecture.md` D10), so this is now the
> **structured surface beneath the chat** rather than the first thing a user
> sees — and it is what a budget *constraint chip* expands into when tapped. The
> rule survives the change: wherever a budget is entered, it is the main event on
> that surface, never a cramped field in a row of others.

**Conversation thread**
The intake surface. Plain message rows, not bubbles-in-boxes — user text aligned
one way, Amora's the other, generous vertical rhythm per §4. No avatars, no
persona illustration, no name label: Amora is not a character, and giving it a
face invites users to ask it things the database cannot answer.

**No typing-indicator theatre.** Show a real progress state while a request is in
flight, and nothing at all otherwise. §6 forbids animating for delight, and a
simulated "thinking" pause is the purest form of that — it spends frames on
mid-range Android to make the product feel slower than it is.

**Constraint chip** (the component that makes the agent trustworthy)
The extracted constraints — budget, time, starting barangay, what you own —
rendered as chips above the plan, each one tappable to correct.

This is the most important new component in the app, because it is what stops
conversation becoming guesswork the user cannot see. The model's reading of a
request is always **shown, never assumed.** A chip must read as *editable* — it
carries a value the user can change, not a pronouncement the system has made. Use
the `small` radius and an affordance that says "tap me", and never render a chip
in a state the user cannot reach and fix.

A constraint the model could not determine appears as an **unfilled** chip
prompting for it ("How much?"), not as a silent default. A wrong assumption the
user can see and fix costs a tap; a wrong assumption hidden behind confident
prose costs their evening.

**Starter chips**
The empty state of the conversation thread: two or three concrete openers
("Tonight", "This weekend", "Under ₱200"). They solve the blank page, and a
tapped chip is already a structured value — it skips extraction entirely
(`00-architecture.md` §7 step 0), so the friendliest path is also the cheapest.

Consistent with the existing empty-state rule below: never present an empty
thread with nothing to press.

**Community list** (Phase 7 — a filtered list, never a feed)
Published plans, ranked by **budget fit**, never by recency. Cards are
photo-forward like the plan card, but the sort order is a query result, not a
timeline. No follower graph, no like counts, no comment threads — all already on
CLAUDE.md's not-building list, and all of them are what would turn this into a
vanity feed.

The reason is not taste: **ranking specifies behaviour.** Rank by recency and
photos and people optimise for photos, which costs the structured budget data that
makes a shared plan worth more than a picture. Rank by budget fit and accurate
budgets are what get rewarded. `00-architecture.md` §9 carries the full argument.

**Empty states**
Never a bare "No results." Always explain and offer an action: "No plans under ₱100
open right now. Try widening to ₱200, or check tomorrow evening."

**Touch targets:** 48×48 dp minimum, no exceptions.

---

## 6. Motion

Minimal. Material default durations and curves. Page transitions from GoRouter
defaults.

Animate only to explain a change: a stop being removed, a total recalculating, a plan
being saved. Never animate for delight alone — this app runs on mid-range Android
over mobile data, and every dropped frame costs more than the polish gains.

Respect the OS reduced-motion setting.

### The one sanctioned exception: the splash

The startup splash animates for its own sake, which the rule above forbids. It is
allowed as a named exception rather than left as a contradiction, because the
first screen is the one place where there is no change to explain and still
something worth saying.

**It is bound by interruption, not by duration.** `AmoraApp` replaces
`StartupSplash` the moment startup resolves, and a warm start is well under a
second — so the animation is *cut off* rather than played. It must therefore look
deliberate at every frame it might die on. A fade-and-rise does. A draw-on, a
scale-then-crossfade, or anything with a payoff at the end does not, because the
payoff is exactly what gets cut.

Holding the splash to a minimum duration would remove the problem and is
**forbidden**: it delays startup, which is the thing `appStartupProvider` exists
to avoid.

Rules for it, and for anything that ever joins it here:

- Under 500 ms, and correct at every intermediate frame.
- Reduced motion renders the **end state**, immediately. Not a shorter animation,
  and not a blank screen.
- Nothing reporting real work may sit inside the animation. The progress
  indicator is outside the fade on purpose: a slow start is precisely when it
  must already be visible.
- No asset dependency. It ships before the mascot art exists and must not look
  broken without it.

---

## 7. Design references

Real screenshots live in `docs/design/references/`, named for what they demonstrate:

```
plan-card-density-airbnb.png
timeline-legs-gmaps.png
budget-input-emphasis.png
memory-feed-strava.png
```

**Use mobile references only.** Web UI does not translate — different layout model,
no hover, a fifth of the width. Converting a web design to Flutter produces a
website squeezed into a phone, which is the exact thing that makes an app feel wrong.

Good sources: Mobbin, Screenlane, UI Sources, m3.material.io. Best source: screenshot
apps already on your phone.

When referencing, be specific about what to take — "the card density from this one",
"the spacing rhythm from that one" — never "make it look like this".

---

## 8. Definition of done for any UI work

- [ ] No hardcoded colours, font sizes, or spacing values
- [ ] Verified in light mode and dark mode
- [ ] Verified on the physical test device (`00-architecture.md` §3), not the emulator
- [ ] Touch targets at least 48 dp
- [ ] Text scales correctly at 1.3× system font size without clipping
- [ ] Loading, empty, and error states all exist
- [ ] Peso amounts follow the budget colour semantics above
- [ ] Any extracted or inferred value is shown to the user and is correctable —
      never applied silently
- [ ] Embedded media loads lazily and has a visible fallback. A webview player is
      the heaviest thing in the app; it must not load until tapped, and an
      embed-disabled video must offer "open in YouTube" rather than an error

## 9. Primary UI reference: Brilliant (iOS)

Reference: Brilliant, browsed on Mobbin. Chosen for its register — approachable and generous without being childish, which is the tone Amora needs when asking someone to say out loud that they have ₱100 to spend.

What we take from it

Generous whitespace. Content breathes. Screens do one thing. When in doubt, add space rather than adding an element. This is the single most transferable quality.

Large rounded cards as the primary container. Radius 12–20, flat fills, no heavy shadows. Cards carry meaning; the space between them carries hierarchy.

One confident accent against near-neutral surfaces. Our deep rose #B4436C does the job Brilliant's accent does. Everything else stays quiet. Resist the urge to give each category its own colour.

Friendly, clear type hierarchy. Large headers, obvious sizing steps, short lines. No dense paragraphs anywhere in the product.

Minimal chrome. Few persistent bars, no decorative dividers, no boxes inside boxes. Content-forward.

Real dark mode. Deep near-black surfaces, not mid-grey. Our M3 dark scheme already handles this — verify it, don't override it.

What we do NOT take from it

Brilliant is iOS. Amora is Material 3. Mixing the two is what makes an Android app feel subtly wrong. Specifically avoid:

collapsing large-title headers
iOS segmented controls (use M3 SegmentedButton or chips)
back-chevron-with-label (use the Material back arrow)
iOS-style modal sheet chrome (use M3 bottom sheets)
SF Symbols icon language (use Material Symbols)

Take the spacing, the card generosity, and the colour restraint. Leave the navigation patterns.

The one substitution that matters

Brilliant leans on illustration. Amora leans on photographs.

Their accent art is drawn and abstract. Ours is a park, a plate of food, a sunset, a user's own memory. Same visual generosity, different content — which means:

Cards need photo treatments: consistent aspect ratios, subtle overlay scrims where text sits on an image, graceful placeholders before load.
The chrome must stay quieter than Brilliant's, because our photos already supply the colour and warmth that their illustrations do.
Never commission or generate illustration to fill an empty state. Use type and a clear action instead — see section 5.
Screens where this reference applies most
Plan card list — card density, spacing rhythm, cost prominence
Budget input — single-purpose screen, large friendly input, lots of air
Resource picker — chip grid, playful but legible selection states
Memory timeline — photo-forward cards, generous vertical spacing
Conversation thread — generous whitespace and short lines matter more here than anywhere; a cramped chat reads as a support widget, not a planner
Screens where it does not

Plan detail with map and timeline. Brilliant has no equivalent. Reference Google Maps directions instead: numbered stops, per-leg mode and cost, a scannable vertical list beneath the map.

**The conversation stops at the itinerary.** Intake is a chat; the plan is not. Once constraints resolve, the result is a card, a map and a timeline — a document the user reads, keeps and walks around with, not a message they scroll back through. Place detail and embedded tutorials (Phase 4) open from a stop, and never as chat turns. Anything that would make the plan itself feel like a transcript is wrong.

Storage

Save screenshots to docs/design/references/ with descriptive names, e.g. brilliant-card-density.png, brilliant-spacing-rhythm.png. Mobile screenshots only. When referencing one in a prompt, say what to take from it specifically — "the card density here", not "make it look like this".

---

## 10. Specified, not built

**Nothing in this section exists in the app.** It is written down so the shape is
agreed before it is built, and so a future session does not re-derive it or,
worse, half-build it early. Each entry names what blocks it.

Read this section together with `CLAUDE.md`'s "Explicitly NOT building yet" list.
Where the two disagree, that list wins.

### 10.1 Navigation — BUILT 2026-08-18

Moved out of "specified, not built". `lib/app/shell.dart`, wired through
`StatefulShellRoute.indexedStack` in `lib/app/router.dart`.

| Order | Destination | Route | Status |
|---|---|---|---|
| 1 | Plan | `/intake` | built |
| 2 | Memories | `/memories` | built |
| 3 | Profile | `/profile` | built |
| 4 | Feed | — | **Phase 7. Not stubbed.** |

**Feed is not a placeholder.** An empty or disabled fourth tab makes the app
look dead, and Phase 7 is a filtered list rather than a community feed, which
`CLAUDE.md`'s not-building list rules out. A test asserts the bar has exactly
three destinations and that no "Feed" label exists — that assertion is what
stops it arriving early as a stub.

**Three shipped at once, with Profile.** Material's floor is three destinations,
so the bar could not arrive with Plan and Memories alone and grow later.

**Home is gone.** `HomeScreen`'s entire content was a column of buttons, which
*was* the navigation — once the bar existed there was nothing left for it to do.
Its non-planning content (greeting, owned-resource count, preferences, token
gallery, sign out) moved to Profile. `/` is kept as a redirect to `/intake`
rather than deleted, so a deep link or an older build's initial location lands
somewhere real instead of on GoRouter's error page.

**`indexedStack`, not one navigator.** Each branch keeps its own `Navigator` and
its own state, so switching away from a half-finished conversation and back does
not reset it. A rebuilt intake would discard in-flight constraints, and
recovering them costs a model call on a tier capped at five requests a minute.
There is a test that fills a chip, switches tabs, returns, and asserts the chip
survived.

**What is in a branch and what is not.** Ideas and saved plans sit *inside* the
Plan branch: they are places you go while planning, so the bar stays and back
returns to that tab. Plan detail, place detail, add-stop and the plan-request
form sit **outside** the shell — Material persists the bar across top-level
destinations, not across every screen.

**Tapping the active destination returns to its root**
(`goBranch(initialLocation: index == currentIndex)`), which is what a user
reaches for when they are three screens deep and want out.

**Ideas and saved plans moved into the intake app bar**, since the button column
that used to hold them is gone. Ideas is reachable from the *filled*
conversation too, not only the empty state: "what could we even do" is a thought
someone has halfway through, and an affordance that disappears once you start
typing is not an affordance.

> ⚠️ **Three app-bar actions is the known risk on this screen** — two icons plus
> the "Use the form" text button. Verify at 1.3× font scale before calling it
> done; if it crowds, "Use the form" is the one that has to keep its words,
> because it is the extraction fallback.

### 10.2 Preferences — BUILT 2026-08-18

Moved out of "specified, not built". Migrations `20260818121939` and
`20260818121957`; screen at `lib/features/preferences/preferences_screen.dart`;
vocabulary in `lib/models/preferences.dart`.

`profiles` gained `companion_type`, `interests text[]` and
`usual_budget_php_cents`. Everything here is optional — nothing gates on it, and
clearing every answer is a supported state.

**Companion type** — single select, and **only `Partner` is offered**.

The column's check constraint permits `partner`, `friends`, `family`, `solo` and
`group`, so widening the persona later is a change to one Dart list rather than a
migration (`00-architecture.md` §11). But everything past `Partner` *is* persona
expansion, which D1 scopes out and `CLAUDE.md`'s not-building list names
explicitly — so the picker offers one value and a test asserts the other four are
absent.

**Interests** — multi select, no minimum. **Rank, never filter.**

A user who ticks nothing must get the same activities as one who ticks
everything; only the order moves. Enforced in `retrieve_activities` — with no
interests every row scores the same, so the empty case is not a special case, it
is the identical query — and asserted from Dart at the provider seam, because the
way this breaks is a well-meaning pre-filter added to `ideasProvider`.

`Outdoors and nature` · `Food and coffee` · `Cooking together` ·
`Arts and crafts` · `Sports and fitness` · `Music` · `Games and staying in`

> **Seven, not the twelve first specified, and the slug is an
> `activities.category` value rather than a separate vocabulary.** Ranking
> happens on `category`, so an interest matching no category could not change a
> single result. Six of the original twelve — Photography, Films and shows,
> Shopping, Faith and community, Learning something new, Just walking around —
> were exactly that: a dead control with a nice label, which is the same defect
> as the 18 resource rows no activity required.
>
> Finer-grained interests need an `activities.tags` column to rank against. That
> is a real feature and worth doing; it is not a relabelling of this one.

**Usual budget** — single select. A **default for the intake budget chip, never a
cap**, and **per outing for the whole party** (`00-architecture.md` §9).

`free` · `₱200` · `₱500` · `₱1,000` · `₱2,000`

> **Amounts, not bands.** The value's only job is to prefill a number, and a band
> cannot prefill anything without silently choosing a figure from inside itself.
> There is no top band for the same reason the sheet has no maximum: the picker
> is a shortcut and the budget sheet still accepts anything typed.

**The saved budget seeds the sheet, not the constraint.** Writing it into
`IntakeConstraints` would be an inferred value applied silently, which §8
forbids, and it would suppress the starter chips — those only show while nothing
is established. Opening the sheet on their usual number is visible and
correctable before it commits.

Selection styling follows the resource picker: chip grid, `FilterChip` for the
multi-select, `ChoiceChip` for the single-selects, selected state carried by fill
and check rather than by colour alone. Re-tapping a selected `ChoiceChip` clears
it, because every answer here has to be un-answerable.

### 10.3 Map above the timeline

Blocked on: real coordinates. All 15 `places` rows are `test-*` with invented,
clustered coordinates — a map of them draws one blob with 72 m legs, so the
layout cannot be judged, let alone accepted.

- Map sits **above** the stop list, not behind it and not on a separate tab.
- Stops are **numbered**, and the numbers match the timeline exactly. Reference
  Google Maps directions: numbered pins, a scannable vertical list beneath.
- **Auto-routed by default.** The user never has to place anything to get a
  usable plan.
- A pin is **draggable to adjust**. A drag is a correction to *this plan only* —
  it must never write back to `places`, which is curated data (invariant 5).
- Map height is capped so at least one stop row is visible beneath it at 1.3×
  font scale. A map that fills the viewport hides the thing it is annotating.

**A stop with no place attached** is the case that decides the design, because
Phase 5 lets users add stops and Ideas produces activities that are not anywhere:

- It appears in the timeline with its number, as normal.
- It gets **no pin**, and the auto-route draws **through** it without a
  waypoint — the leg either side connects the nearest stops that do have
  coordinates.
- Its timeline row carries a quiet "not on the map" affordance rather than an
  error. It is not a failure; "watch the sunset" has no address.
- If **no** stop has coordinates, the map is **absent**, not empty. An empty map
  of Bocaue is a bare empty state, which §5 forbids.

### 10.4 Price breakdown

Partly blocked. Split deliberately, because one half is buildable and building it
alone would be a mistake.

Lines, in order: **fares · food · materials · activities · gifts**, then the
total.

- **Fares need the dormant places layer.** They come from `transit_fares` via
  `fare_for`, and a leg is only priced once both ends have real barangays.
- **Materials and activities work today** off `activities` alone.

**Recommendation: do not build the activities-only version.** Invariant 3 says
the app performs no arithmetic — a breakdown is a *rendering* of what
`cost_generated_plan` returns, so it cannot ship ahead of the server emitting
those lines anyway. And fares are the line that matters most: a ₱25 tricycle is
around 12% of a Bocaue date budget (§12), so a breakdown that omits them teaches
the wrong shape and is rebuilt the week real places land.

Every amount follows §2's budget colour semantics, including the ₱0 rule: "Total
free" is right, "fares free" is not.

### 10.5 Shared plan detail — Phase 7

Blocked on: Phase 7, which has not started.

A shared plan renders **itinerary, map and price breakdown** — the same three
components as an owned plan, and deliberately the same components rather than a
prettier read-only variant, so there is one renderer to keep correct.

What differs from an owned plan:

- No edit affordances at all — no reorder handle, no ✕, no clock, no "Add a
  stop".
- **Prices are the sharer's, and are labelled as such**, with the date they were
  recorded. A price is a decaying fact (§10.4 doctrine in
  `00-architecture.md`); presenting last month's total as today's is the failure
  mode this whole product exists to avoid.
- "Make this mine" copies it into the viewer's own plans, re-costed at today's
  prices, rather than letting two users share one row.

It is a **filtered list, not a feed**. Ranking by recency would make people
optimise for photographs, which costs the price data that makes a shared plan
worth anything.

### 10.6 A national map of where plans have happened — cut

Proposed as a nav destination showing the Philippines with pins wherever plans
have happened. **Recommended cut, and recorded here rather than dropped silently
so it is not re-proposed.**

- **It does not serve the job.** Amora answers "what do we do tonight, under
  ₱X". A map of where you have already been is retrospective, and `/memories`
  already answers it for the only geography that holds data.
- **It advertises the coverage gap as the headline visual.** The app ships
  nationwide and knows only Bocaue. A map that is 99% empty is a full-screen
  bare empty state promoted to a permanent nav slot — the exact thing the
  coverage rules say never to show.
- **It costs a nav slot** against Plan and Memories, which are the product.

Where it *is* honest: the Phase 9 marketing site, as "here is where Amora
works". That is positioning rather than a broken feature, and it improves as
coverage grows instead of mocking it.
