# CLAUDE.md — Amora

## What this is

Amora replaces five tabs with one answer. A user says what they want in their own
words — their budget, who they're with, where they are, what they already own. We
read that into constraints, show them back so they can be corrected, and return
three complete, costed, mappable plans — real local places, real prices, real
jeepney and tricycle fares. Then they edit it to fit their life, go do it, and
record what actually happened.

**The conversation is the intake, not the answer.** The model reads the request
and never sources a fact in it. See `docs/00-architecture.md` D2 and D10.

**MVP: couples aged 18–28, Bocaue, Bulacan only, one job — "plan tonight or this
weekend, under ₱X, with what we already have."**

Free forever to users. Revenue much later from local business placements.

**The moat is the curated local database, not the AI.** Any chatbot generates date
ideas. Almost none know that this café is actually open, actually costs ₱180, and
that the tricycle there is ₱25.

---

## Working agreement (non-negotiable)

- **Never generate the whole app.** Work one phase at a time, per `docs/00-architecture.md`.
- **Use plan mode.** Present a plan and wait for approval before editing files.
- **After completing a phase, STOP.** Do not begin the next one.
- **Never implement a future phase early**, even if it seems trivial.
- **Never modify files unrelated to the current phase.** Flag it and wait instead.
- **Explain architectural decisions before implementing them.**
- Every phase must: compile, run on the physical test device, meet its written
  acceptance criteria, and land as one clean Git commit. The emulator is not an
  acceptable substitute — see `docs/00-architecture.md` §3 ("Development device").
- **If you think I'm wrong, say so directly and propose the alternative.** Do not
  implement something you believe is a mistake without flagging it first.
- Prefer maintainability over speed. Prefer boring over clever.
- I am new to Flutter. Explain unfamiliar patterns briefly as you introduce them.

---

## Stack (decided — do not substitute)

| Layer | Choice | Version |
|---|---|---|
| App | Flutter (Dart), Android only for now | Flutter 3.44.8 / Dart 3.12.2 |
| State | Riverpod | latest stable, pinned in `pubspec.lock` at Phase 0 |
| Routing | GoRouter | latest stable, pinned in `pubspec.lock` at Phase 0 |
| Design | Material 3 + ThemeExtension | ships with the Flutter SDK |
| Maps | `flutter_map` + OpenStreetMap/CARTO tiles | latest stable, pinned in `pubspec.lock` at Phase 0 |
| Distance | Haversine, computed locally | — |
| Backend | Supabase free — Postgres, Auth, Storage, Edge Functions, RLS | — |
| Photos | Supabase Storage, compressed client-side | — |
| AI | Google Gemini Flash, free API tier, called from an Edge Function | — |
| Distribution | `flutter run` over wireless debugging / sideloaded APK | — |

Full rationale for each choice, plus the data-fetching pattern (repository layer,
Riverpod providers, error/loading handling, Edge Function calls): see
`docs/00-architecture.md` §3 ("Core stack") and §4 ("Data fetching & API strategy").

The Flutter project lives at `apps/mobile/`. Every `flutter` command
(`flutter run`, `flutter pub add`, `flutter analyze`, ...) runs from there, not the
repo root — see `docs/00-architecture.md` §2 ("Repository structure") for the full
monorepo layout and why.

**Do not add a dependency without asking.** Justify it against what's installed.

**Never use these:** `google_maps_flutter` (requires a Google Cloud billing account),
Cloudflare R2 (requires a card), any paid API, any service requiring a credit card.
This project must cost ₱0 to build and run. If a task seems to need a paid service,
stop and tell me — there is always a free path, or the feature waits.

**Web search may produce candidates, never rows.** Search — including AI-assisted
search over Reddit, Facebook or YouTube — is a research aid for finding places
worth walking to. Its output goes in `supabase/seed/candidates/`, never in
`places.csv`. Agreement across sources measures copying, not truth, and it cannot
detect a change younger than the corpus. A `curated` row means a person stood at
the door. Full reasoning: `docs/00-architecture.md` §10.4.

Note: shadcn/ui, MagicUI, and Impeccable are web-only. They are reserved for the
phase-9 Next.js site and must never be referenced in Flutter work.

---

## Architectural invariants

Breaking any of these is a bug, not a style choice.

### 1. The model never invents facts

Gemini composes plans from **retrieved candidates only**. It receives a list of place
IDs and activity IDs and may reference only those. It never produces a place name,
address, price, fare, or opening time from its own knowledge.

**This binds the extraction call too.** Reading a user's request into constraints
(`docs/00-architecture.md` §7 step 0) is a second Gemini call that receives no
candidates at all — so it may emit **constraint values only**: a budget, a time, a
barangay, an occasion bucket. It must never emit a place or activity name, and a
user naming somewhere we have no row for ("take me to that café on the highway")
resolves to a constraint or a question, never to a suggestion. A conversational
intake widens what the user may *say*; it widens nothing about what we may
*claim*.

### 2. The server validates every generated plan

Reject any `place_id` or `activity_id` outside the candidate set. Retry once with a
corrective message, then fail loudly. Never render an unvalidated plan. Log every
rejection.

Extraction output is validated on the same principle: a budget must parse to an
integer, an origin must match a known barangay, a time must resolve to an instant.
Anything that fails is asked about, never guessed — and is shown to the user as a
correctable chip either way.

### 3. The model does no arithmetic

All costs, fares, and totals are computed server-side from database rows. Gemini may
not sum, estimate, or round money.

### 4. Secrets never reach the device

The Gemini API key lives only in Supabase Edge Function secrets. The Flutter app
holds only the Supabase URL and anon key, loaded from `.env`, which is gitignored.

### 5. User edits are the only sanctioned exception

Users may add their own stops. Those land as `source='user'`,
`verification_tier='user_submitted'`, and are **excluded from retrieval** for every
other user until manually promoted. One bad row must never poison the shared data.

### 6. Row Level Security is mandatory

Every table gets RLS in the migration that creates it. A user must not be able to
read another user's plans, memories, or resources. Enforce in Postgres, never in Dart.

### 7. Every plan edit is logged

Write a `plan_edits` row for every add, remove, reorder, and retime. If most users
delete the same suggested stop, that recommendation is bad and I need to know.

---

## Conventions

- Money is integer centavos (`_php_cents`). Never floats, never doubles.
- **Money is per person.** `places.price_min_php_cents` is what *one* person
  spends; the same for `activities` budgets. Totals multiply by `party_size` (2
  while D1 holds). Fares are the exception that proves it: a jeepney charges each
  passenger, a tricycle special trip charges once for the vehicle, so
  `transit_fares.is_per_person` decides. The user's budget always means the whole
  outing — ₱200 for the date, not each. See `docs/00-architecture.md` §9.
- Distances in metres, durations in minutes, both integers.
- Times stored UTC, displayed `Asia/Manila`.
- All Supabase access goes through a typed repository layer in `lib/data/`.
  No raw queries inside widgets.
- All AI calls go through the Edge Function. Never call Gemini from Dart.
- Riverpod: `ref.watch` in `build`, `ref.read` in callbacks. Always handle
  `.when(data:, loading:, error:)`.
- Material 3 only. No hardcoded colors or font sizes — use `ColorScheme` roles and
  `TextTheme`. Define custom tokens via `ThemeExtension`.
- `const` constructors everywhere possible. Dispose every controller.
- GoRouter for all navigation. Use `PopScope`, never the deprecated `WillPopScope`.

Concrete file layout (`apps/mobile/lib/data/`, `lib/models/`, `lib/features/`) and the
full repository → provider → widget chain: see `docs/00-architecture.md` §4.

---

## Handoff file

`docs/HANDOFF.md` is the context bridge for fresh sessions — both new Claude Code
sessions and the web chat I use for planning.

Update it whenever you print a batch of commit messages, before I apply them.
Treat it as part of the commit batch, not an afterthought.

Keep it to what the other docs don't say:
- current phase, what's done, what's next
- environment and device state
- decisions made in conversation that never landed in another doc
- gotchas already hit, so they aren't repeated
- state of the seed data

Do not duplicate `docs/00-architecture.md`. If something belongs there, put it
there and leave `HANDOFF.md` short. Target one page.

---

## Explicitly NOT building yet

Do not scaffold, stub, or "prepare for" any of these:

worldwide · multi-language · multi-currency · flights · hotels · reservations ·
multi-day trip planning · ride-hailing · voice AI · wearables · Android Auto ·
CarPlay · real-time collaboration · community feed · comments · direct messages ·
follower graphs · merchant dashboard · billing · iOS · families and solo personas

If I ask for one of these before its phase, remind me of this list.

**The line, when something sounds close to in-scope:** Amora plans *time within a
place you are already in*. Planning *movement between places you are not in yet*
is a different product — see `docs/00-architecture.md` §12, which works through
the cases and says why the moat is worth nothing on the far side of that line.
"Day 3 in Manila with ₱500" is Amora. "Plan my Cebu trip" is not.
