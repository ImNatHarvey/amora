-- Phase 0 — core schema.
--
-- Creates only the seven tables Phase 0 needs. The plans/plan_items/plan_legs/
-- plan_cache tables land in Phase 3, plan_edits in Phase 5, memories and
-- place_reports in Phase 6, placement_events in Phase 10 — see
-- docs/00-architecture.md §5 for the full target schema and its phasing note.
--
-- Conventions enforced here (CLAUDE.md):
--   * money is integer centavos, never a float, and column names end _php_cents
--   * timestamps are timestamptz, stored UTC, displayed Asia/Manila by the app
--   * RLS is enabled on every table in the same migration that creates it

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  city text,
  home_lat double precision,
  home_lng double precision,
  created_at timestamptz not null default now()
);

comment on table public.profiles is
  'One row per authenticated user. id mirrors auth.users.id.';

-- ---------------------------------------------------------------------------
-- resource_catalog — the fixed list of things a user might already own
-- ---------------------------------------------------------------------------
create table public.resource_catalog (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  category text,
  icon text,
  created_at timestamptz not null default now()
);

comment on column public.resource_catalog.slug is
  'Stable natural key so re-importing the seed CSV updates rather than duplicates.';

-- ---------------------------------------------------------------------------
-- user_resources — what this user actually owns
-- ---------------------------------------------------------------------------
create table public.user_resources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  resource_id uuid not null references public.resource_catalog (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, resource_id)
);

-- ---------------------------------------------------------------------------
-- places — the curated local database. This is the moat (docs D3).
-- ---------------------------------------------------------------------------
create table public.places (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  category text not null,
  lat double precision not null,
  lng double precision not null,
  address text,
  barangay text,
  city text not null,
  opening_hours jsonb,
  price_min_php_cents integer not null default 0
    check (price_min_php_cents >= 0),
  price_max_php_cents integer
    check (price_max_php_cents >= 0),
  indoor boolean not null default false,
  sunset_facing boolean not null default false,
  verification_tier text not null default 'curated'
    check (verification_tier in ('curated', 'user_submitted')),
  source text not null default 'owner'
    check (source in ('owner', 'user')),
  submitted_by_user_id uuid references public.profiles (id) on delete set null,
  verified_at timestamptz,
  social_url text,
  contact_number text,
  notes text,
  created_at timestamptz not null default now(),
  constraint places_price_range_valid
    check (price_max_php_cents is null
           or price_max_php_cents >= price_min_php_cents)
);

-- Phase 2 retrieval filters on city + budget, then on a lat/lng bounding box.
create index places_city_price_idx
  on public.places (city, price_min_php_cents);
create index places_lat_lng_idx
  on public.places (lat, lng);

-- ---------------------------------------------------------------------------
-- place_notes — the "Reddit layer": lived experience about a place
-- ---------------------------------------------------------------------------
create table public.place_notes (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places (id) on delete cascade,
  body text not null,
  -- not null so the (place_id, source_label) upsert key actually works;
  -- NULLs never conflict with each other in Postgres.
  source_label text not null,
  added_at timestamptz not null default now(),
  unique (place_id, source_label)
);

-- ---------------------------------------------------------------------------
-- activities
-- ---------------------------------------------------------------------------
create table public.activities (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  category text,
  min_budget_php_cents integer not null default 0
    check (min_budget_php_cents >= 0),
  max_budget_php_cents integer
    check (max_budget_php_cents >= 0),
  duration_minutes integer check (duration_minutes > 0),
  required_resource_ids uuid[] not null default '{}',
  weather_dependent boolean not null default false,
  is_diy boolean not null default false,
  tutorial_url text,
  created_at timestamptz not null default now(),
  constraint activities_budget_range_valid
    check (max_budget_php_cents is null
           or max_budget_php_cents >= min_budget_php_cents)
);

-- ---------------------------------------------------------------------------
-- transit_fares — proprietary data; no API knows these (docs D5)
-- ---------------------------------------------------------------------------
create table public.transit_fares (
  id uuid primary key default gen_random_uuid(),
  from_area text not null,
  to_area text not null,
  mode text not null
    check (mode in ('walk', 'tricycle', 'jeepney', 'bus', 'drive')),
  fare_php_cents integer not null check (fare_php_cents >= 0),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique (from_area, to_area, mode)
);

-- ---------------------------------------------------------------------------
-- Row Level Security (CLAUDE.md invariant 6)
--
-- Enabled on every table. Note that enabling RLS with no policy for a given
-- command denies that command outright — which is the intent for every write
-- path below. Seeding runs as the postgres role and bypasses RLS.
--
-- auth.uid() is wrapped in a scalar sub-select so Postgres evaluates it once
-- per query rather than once per row.
-- ---------------------------------------------------------------------------
alter table public.profiles         enable row level security;
alter table public.resource_catalog enable row level security;
alter table public.user_resources   enable row level security;
alter table public.places           enable row level security;
alter table public.place_notes      enable row level security;
alter table public.activities       enable row level security;
alter table public.transit_fares    enable row level security;

-- Reference data: world-readable, no client writes.
create policy resource_catalog_read on public.resource_catalog
  for select to anon, authenticated using (true);

create policy activities_read on public.activities
  for select to anon, authenticated using (true);

create policy transit_fares_read on public.transit_fares
  for select to anon, authenticated using (true);

-- places: curated rows are public. A user's own submissions are visible only to
-- them, which is CLAUDE.md invariant 5 enforced in Postgres — one bad row can
-- never leak into anyone else's retrieval. No insert policy: user submissions
-- are Phase 5.
create policy places_read on public.places
  for select to anon, authenticated
  using (
    verification_tier = 'curated'
    or submitted_by_user_id = (select auth.uid())
  );

-- place_notes inherit their parent place's visibility.
create policy place_notes_read on public.place_notes
  for select to anon, authenticated
  using (
    exists (
      select 1
      from public.places p
      where p.id = place_notes.place_id
        and (
          p.verification_tier = 'curated'
          or p.submitted_by_user_id = (select auth.uid())
        )
    )
  );

-- profiles: strictly owner-only, in every direction.
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));

create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- user_resources: owner-only, all commands.
create policy user_resources_select_own on public.user_resources
  for select to authenticated using (user_id = (select auth.uid()));

create policy user_resources_insert_own on public.user_resources
  for insert to authenticated with check (user_id = (select auth.uid()));

create policy user_resources_delete_own on public.user_resources
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Grants
--
-- RLS narrows what a role may reach; grants decide whether it may attempt the
-- command at all. Both are stated explicitly so replaying this file against a
-- fresh project reproduces the schema exactly, without depending on whatever
-- default privileges happen to be configured.
-- ---------------------------------------------------------------------------
grant select on public.resource_catalog to anon, authenticated;
grant select on public.activities       to anon, authenticated;
grant select on public.transit_fares    to anon, authenticated;
grant select on public.places           to anon, authenticated;
grant select on public.place_notes      to anon, authenticated;

grant select, insert, update on public.profiles       to authenticated;
grant select, insert, delete on public.user_resources to authenticated;
