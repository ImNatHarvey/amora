-- Phase 6 — what actually happened.
--
-- Every phase before this one makes a promise: real places, real prices, real
-- fares. This is the first table that hears back. It is split from the
-- complete_plan migration that follows for the same reason Phase 5 split its
-- two: this one answers "what may be recorded", that one answers "how a
-- completion is written". Each is verifiable alone.
--
-- Nothing here READS a report. Correction — median of three, the 20% threshold,
-- the two-closures quarantine, provenance labels in the UI — is Phase 6b, and
-- it is gated on report volume rather than on code (§10.5). Phase 6's whole job
-- is to capture a corpus in a shape 6b can use without a data migration first.

-- ---------------------------------------------------------------------------
-- memories — the keepsake, and the reason anyone opens the app a second time
--
-- plan_id is UNIQUE, and that is load-bearing rather than tidy. Completion
-- writes a memory and one place_report per stop in one transaction; a second
-- completion of the same plan would duplicate every one of those reports, and
-- 6b takes a MEDIAN over them. Two copies of one evening's figure would let a
-- single user move a price they could otherwise only nudge — the anti-gaming
-- rule in §10.5 defeated not by an adversary but by a double tap. The unique
-- constraint makes that a database error instead of a silent skew.
--
-- actual_spend_php_cents is a PARTY total, matching the budget it will be read
-- against. It is derived server-side by complete_plan (invariant 3) — summed
-- from the per-stop figures and the fares actually paid, never sent as a total
-- by the device.
--
-- photo_path is nullable, and nothing about a completion depends on it. The
-- correction loop must not be gated on a photograph: a couple who forgot to
-- take one still knows what they spent, and that is the row 6b needs.
-- ---------------------------------------------------------------------------
create table public.memories (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null unique references public.plans (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  photo_path text,
  caption text,
  actual_spend_php_cents integer check (actual_spend_php_cents >= 0),
  rating smallint check (rating between 1 and 5),
  created_at timestamptz not null default now()
);

comment on table public.memories is
  'One per completed plan. plan_id is unique so a double completion cannot '
  'duplicate the place_reports written beside it, which 6b takes a median over.';

comment on column public.memories.actual_spend_php_cents is
  'A PARTY total in centavos, derived by complete_plan from the per-stop '
  'figures plus the fares actually paid. Never computed on the device '
  '(invariant 3).';

comment on column public.memories.photo_path is
  'Object path in the private memory-photos bucket, <uid>/<plan_id>-<epoch>.jpg. '
  'Null is ordinary: a completion with no photo still writes every report.';

-- ---------------------------------------------------------------------------
-- place_reports — crowdsourced price truth, one row per STOP
--
-- Not one per plan. §10.5 corrects prices per place, and a single plan-level
-- spend figure cannot be attributed back to the café that was wrong. This is
-- the same grain lesson plan_edits.target_place_id records.
--
-- reported_cost_php_cents is PER PERSON, and this is the sharpest edge in the
-- phase. plan_items.est_cost_php_cents is a party total (write_plan_stops
-- multiplies by party_size), but the column 6b compares a median AGAINST is
-- places.price_min_php_cents, which §9 defines as what ONE person spends. The
-- user is asked for the party figure, because that is the only number a human
-- actually knows; complete_plan divides by plans.party_size before storing it
-- here. Store the party figure instead and every 6b median comes out at twice
-- the truth, looking entirely plausible.
--
-- The check constraint is §10.5's asymmetry, in one line. A price report counts
-- only from a completed plan — that raises the cost of gaming a price from
-- typing to travelling. A closure report does NOT require a plan, because the
-- failure it reports is self-concealing (§10.2): a couple who finds a locked
-- door abandons the plan and never completes it, so requiring completion would
-- blind us to exactly the error that costs the most.
--
-- created_at is not decoration. A report that cannot be aged is worthless to
-- 6b, whose rules are all windowed — two closures within 30 days, one report
-- per user per place per 30 days.
-- ---------------------------------------------------------------------------
create table public.place_reports (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  reported_cost_php_cents integer check (reported_cost_php_cents >= 0),
  still_open boolean not null,
  note text,
  plan_id uuid references public.plans (id) on delete set null,
  created_at timestamptz not null default now(),

  constraint place_reports_price_needs_a_plan
    check (reported_cost_php_cents is null or plan_id is not null)
);

comment on table public.place_reports is
  'One row per stop of a completed plan, plus standalone closure reports. '
  'Append-only: no update or delete policy, because 6b ages these rows and a '
  'report that can be rewritten after the fact is not evidence.';

comment on column public.place_reports.reported_cost_php_cents is
  'PER PERSON, in centavos — comparable with places.price_min_php_cents (§9). '
  'complete_plan divides the party figure the user entered by plans.party_size. '
  'Storing the party figure here would double every median 6b computes.';

comment on constraint place_reports_price_needs_a_plan on public.place_reports is
  'Section 10.5: a price report requires a completed plan; a closure report '
  'does not. '
  'The asymmetry is deliberate — closures are the self-concealing failure.';

-- ---------------------------------------------------------------------------
-- Indexes
--
-- place_reports (place_id, created_at) is literally 6b's query: the reports for
-- one place, within a window. The FK indexes follow the precedent set in
-- 20260731004221, and memories (user_id, created_at) is the timeline screen's
-- only read.
--
-- Expect all of these in the performance advisor's unused_index list. That
-- measures the dataset, not the schema — plans sit at zero rows between test
-- runs, and Postgres will not choose an index on a table this small. HANDOFF.md
-- records the same noise for six existing indexes.
-- ---------------------------------------------------------------------------
create index place_reports_place_created_idx
  on public.place_reports (place_id, created_at desc);
create index place_reports_user_id_idx  on public.place_reports (user_id);
create index place_reports_plan_id_idx  on public.place_reports (plan_id);
create index memories_user_created_idx  on public.memories (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- RLS — invariant 6, in the migration that creates the tables
--
-- Both are user-scoped and readable only by their owner. A memory is a private
-- keepsake; publishing one is Phase 7 and will need its own policy, deliberately
-- written then rather than left ajar now.
--
-- place_reports is readable only by its author too, which is worth stating
-- plainly because 6b will need to read ALL of them: it does that as the service
-- role, from server code, exactly as plan_cache is read today. A user has no
-- reason to see another user's report, and a readable corpus is a scrapeable one.
--
-- No update and no delete policy on either, and no grant for either. Same shape
-- as plan_edits and for the same reason: append-only by omission. A user who
-- could delete a report could withdraw evidence that a place has closed.
-- ---------------------------------------------------------------------------
alter table public.memories enable row level security;

create policy memories_select_own on public.memories
  for select to authenticated using (user_id = (select auth.uid()));

create policy memories_insert_own on public.memories
  for insert to authenticated with check (user_id = (select auth.uid()));

grant select, insert on public.memories to authenticated;

alter table public.place_reports enable row level security;

create policy place_reports_select_own on public.place_reports
  for select to authenticated using (user_id = (select auth.uid()));

create policy place_reports_insert_own on public.place_reports
  for insert to authenticated with check (user_id = (select auth.uid()));

grant select, insert on public.place_reports to authenticated;
