-- Phase 3 — the tables a generated plan lands in.
--
-- plans / plan_items / plan_legs / plan_cache, exactly the set docs
-- 00-architecture.md §5's phasing note assigns to this phase. plan_edits is
-- Phase 5, memories and place_reports are Phase 6, and plan_legs gains
-- actual_fare_php_cents in Phase 6 — none of them are prepared for here.
--
-- Conventions (CLAUDE.md): money is integer centavos, timestamps are
-- timestamptz stored UTC, and RLS is enabled in the same migration that creates
-- the table.

-- ---------------------------------------------------------------------------
-- plans
--
-- A saved plan, as opposed to SimplePlan, which is the transient computed
-- result Phase 2 renders and never stores. The distinction is deliberate and is
-- why the Dart model was not called Plan.
-- ---------------------------------------------------------------------------
create table public.plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text,
  budget_php_cents integer not null check (budget_php_cents >= 0),
  companion_type text,
  occasion text,
  -- The multiplier that turns per-person prices into what the outing costs
  -- (§9). Two while D1 holds; a column rather than a constant so the persona
  -- expansion in §11 is an addition rather than a re-collection.
  party_size integer not null default 2 check (party_size >= 1),
  planned_for timestamptz not null,
  status text not null default 'draft'
    check (status in ('draft', 'active', 'completed')),
  origin text not null default 'generated'
    check (origin in ('generated', 'manual')),
  generated_by_model text,
  created_at timestamptz not null default now()
);

comment on table public.plans is
  'A saved plan. Distinct from the transient SimplePlan the Phase 2 screen '
  'renders, which is never persisted.';

comment on column public.plans.generated_by_model is
  'Which model produced this, or null when the user built it by hand. D8 says '
  'swapping models is a config change; this is what makes that auditable after '
  'the fact.';

-- ---------------------------------------------------------------------------
-- plan_items — the stops, in order
-- ---------------------------------------------------------------------------
create table public.plan_items (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans (id) on delete cascade,
  seq integer not null check (seq >= 0),
  activity_id uuid references public.activities (id) on delete set null,
  place_id uuid references public.places (id) on delete set null,
  start_time timestamptz,
  duration_minutes integer check (duration_minutes >= 0),
  est_cost_php_cents integer not null default 0 check (est_cost_php_cents >= 0),
  note text,
  created_at timestamptz not null default now(),
  unique (plan_id, seq)
);

comment on column public.plan_items.est_cost_php_cents is
  'What the whole party spends at this stop. Computed server-side from the '
  'place row and party_size — invariant 3 keeps money arithmetic out of both '
  'the model and the device.';

comment on column public.plan_items.place_id is
  'Nullable and ON DELETE SET NULL on purpose: a place that is later '
  'quarantined or removed must not delete the memory of a date somebody '
  'actually went on.';

-- ---------------------------------------------------------------------------
-- plan_legs — the journeys between stops
-- ---------------------------------------------------------------------------
create table public.plan_legs (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans (id) on delete cascade,
  from_item_id uuid references public.plan_items (id) on delete cascade,
  to_item_id uuid references public.plan_items (id) on delete cascade,
  seq integer not null check (seq >= 0),
  mode text check (mode in ('walk', 'tricycle', 'jeepney', 'bus', 'drive')),
  distance_m integer check (distance_m >= 0),
  duration_min integer check (duration_min >= 0),
  fare_php_cents integer check (fare_php_cents >= 0),
  created_at timestamptz not null default now(),
  unique (plan_id, seq)
);

comment on column public.plan_legs.from_item_id is
  'Null for the first leg, which starts at the origin rather than at a stop.';

comment on column public.plan_legs.fare_php_cents is
  'Null when no fare has been recorded for this barangay pair. Null is a fact '
  'here, not a missing value: estimating it from distance is the invented '
  'local data D5 exists to forbid, so an unpriced leg is excluded from the '
  'total and the total is labelled a floor.';

comment on column public.plan_legs.mode is
  'One mode per leg today. A day trip out of Bocaue is a bus, then an MRT '
  'ride, then a jeep, which arrives as an additive plan_leg_segments table '
  '(§12.3) — so the UI must render a leg from a list, never assume this '
  'column is the whole answer.';

-- ---------------------------------------------------------------------------
-- plan_cache — the primary cost control (§7 step 2)
--
-- Shared across users, which is safe because the key is a rounded constraint
-- record carrying no personal data, and deliberate because most requests
-- repeat. RLS is enabled with NO policies: this is server-side infrastructure
-- reached only by the Edge Function's service role, never by a device.
-- ---------------------------------------------------------------------------
create table public.plan_cache (
  id uuid primary key default gen_random_uuid(),
  constraint_hash text not null unique,
  payload jsonb not null,
  hit_count integer not null default 0,
  -- Bumped whenever a place price changes or a place leaves retrieval. Without
  -- it a corrected row keeps serving stale totals out of cache forever. This is
  -- needed the first time a seed CSV is re-imported with a corrected price, not
  -- only when Phase 6b's community corrections arrive.
  places_version integer not null default 1,
  created_at timestamptz not null default now()
);

comment on table public.plan_cache is
  'Constraint hash -> generated payload. Shared across users; the key is a '
  'rounded constraint record and carries no personal data. Raw utterance text '
  'must never enter the key (§9).';

-- ---------------------------------------------------------------------------
-- Indexes. Foreign keys are not indexed automatically by Postgres, and every
-- one of these is read on the hot path.
-- ---------------------------------------------------------------------------
create index plans_user_id_idx on public.plans (user_id);
create index plans_user_planned_for_idx on public.plans (user_id, planned_for desc);
create index plan_items_plan_id_seq_idx on public.plan_items (plan_id, seq);
create index plan_items_activity_id_idx on public.plan_items (activity_id);
create index plan_items_place_id_idx on public.plan_items (place_id);
create index plan_legs_plan_id_seq_idx on public.plan_legs (plan_id, seq);
create index plan_legs_from_item_id_idx on public.plan_legs (from_item_id);
create index plan_legs_to_item_id_idx on public.plan_legs (to_item_id);
create index plan_cache_constraint_hash_idx on public.plan_cache (constraint_hash);

-- ---------------------------------------------------------------------------
-- RLS — invariant 6. A user must not read another user's plans.
-- ---------------------------------------------------------------------------
alter table public.plans enable row level security;
alter table public.plan_items enable row level security;
alter table public.plan_legs enable row level security;
alter table public.plan_cache enable row level security;

create policy plans_select_own on public.plans
  for select to authenticated using (user_id = (select auth.uid()));

create policy plans_insert_own on public.plans
  for insert to authenticated with check (user_id = (select auth.uid()));

create policy plans_update_own on public.plans
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy plans_delete_own on public.plans
  for delete to authenticated using (user_id = (select auth.uid()));

-- Items and legs inherit ownership from their plan. Checking through the parent
-- rather than denormalising user_id keeps one source of truth for who owns what.
create policy plan_items_select_own on public.plan_items
  for select to authenticated
  using (exists (select 1 from public.plans p
                 where p.id = plan_id and p.user_id = (select auth.uid())));

create policy plan_items_insert_own on public.plan_items
  for insert to authenticated
  with check (exists (select 1 from public.plans p
                      where p.id = plan_id and p.user_id = (select auth.uid())));

create policy plan_items_update_own on public.plan_items
  for update to authenticated
  using (exists (select 1 from public.plans p
                 where p.id = plan_id and p.user_id = (select auth.uid())))
  with check (exists (select 1 from public.plans p
                      where p.id = plan_id and p.user_id = (select auth.uid())));

create policy plan_items_delete_own on public.plan_items
  for delete to authenticated
  using (exists (select 1 from public.plans p
                 where p.id = plan_id and p.user_id = (select auth.uid())));

create policy plan_legs_select_own on public.plan_legs
  for select to authenticated
  using (exists (select 1 from public.plans p
                 where p.id = plan_id and p.user_id = (select auth.uid())));

create policy plan_legs_insert_own on public.plan_legs
  for insert to authenticated
  with check (exists (select 1 from public.plans p
                      where p.id = plan_id and p.user_id = (select auth.uid())));

create policy plan_legs_update_own on public.plan_legs
  for update to authenticated
  using (exists (select 1 from public.plans p
                 where p.id = plan_id and p.user_id = (select auth.uid())))
  with check (exists (select 1 from public.plans p
                      where p.id = plan_id and p.user_id = (select auth.uid())));

create policy plan_legs_delete_own on public.plan_legs
  for delete to authenticated
  using (exists (select 1 from public.plans p
                 where p.id = plan_id and p.user_id = (select auth.uid())));

-- plan_cache gets no policies at all. RLS on with zero policies denies every
-- role except the service role the Edge Function runs as, which is exactly the
-- intent: a shared cache is server infrastructure, not user data.
