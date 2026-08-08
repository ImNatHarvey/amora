-- Phase 5 — the edit log, and the narrowest possible door for user places.
--
-- Split from the edit_plan migration that follows it because the two answer
-- different questions: this one is "what may a user write", that one is "how is
-- a plan recomputed". Each is verifiable on its own.

-- ---------------------------------------------------------------------------
-- plan_edits — product-quality telemetry (CLAUDE.md invariant 7)
--
-- §5 sketched this with `target_item_id` alone. That cannot answer the question
-- the invariant exists to ask: "if most users delete the same suggested stop,
-- that recommendation is bad". A plan_item id is per-plan, so counting removals
-- by it groups nothing across users — every row is its own group. The durable
-- key is the PLACE, so it is recorded directly.
--
-- This is the same mistake Phase 6's note about place_reports avoids ("one
-- report per stop, not one per plan"): a figure that cannot be attributed back
-- to the café that was wrong is a figure nobody can act on. Getting the grain
-- right here is the difference between Phase 6b being possible and needing a
-- data migration first.
--
-- target_item_id is `on delete set null` on purpose. edit_plan rewrites a
-- plan's items on every edit, so the id this points at is deliberately
-- short-lived — it says "which row in the plan as it stood", which is worth
-- keeping while it exists and worth nothing once it does not.
-- ---------------------------------------------------------------------------
create table public.plan_edits (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  edit_type text not null
    check (edit_type in ('add', 'remove', 'reorder', 'retime')),
  target_item_id uuid references public.plan_items (id) on delete set null,
  target_place_id uuid references public.places (id) on delete set null,
  created_at timestamptz not null default now()
);

comment on table public.plan_edits is
  'One row per add, remove, reorder or retime. Append-only: there is no update '
  'or delete policy, because a log that can be rewritten is not a log.';

comment on column public.plan_edits.target_place_id is
  'The place the edit was about. This is the column telemetry actually groups '
  'by — target_item_id is per-plan and cannot be compared across users.';

-- FK indexes, following the precedent in 20260731004221.
create index plan_edits_plan_id_idx     on public.plan_edits (plan_id);
create index plan_edits_user_id_idx     on public.plan_edits (user_id);
create index plan_edits_target_place_idx on public.plan_edits (target_place_id);
create index plan_edits_target_item_idx on public.plan_edits (target_item_id);

alter table public.plan_edits enable row level security;

create policy plan_edits_select_own on public.plan_edits
  for select to authenticated using (user_id = (select auth.uid()));

create policy plan_edits_insert_own on public.plan_edits
  for insert to authenticated with check (user_id = (select auth.uid()));

-- Deliberately no update or delete policy, and no grant for either.
grant select, insert on public.plan_edits to authenticated;

-- ---------------------------------------------------------------------------
-- places — the insert path, which Phase 0 left open on purpose
--
-- The places_read policy already returns curated rows plus your own
-- submissions, and its comment ends "No insert policy: user submissions are
-- Phase 5". This is that policy.
--
-- All three columns are pinned in the WITH CHECK, and that is the whole of
-- invariant 5 in one expression. Pin only submitted_by_user_id and a user can
-- insert verification_tier = 'curated' — a row that reaches every other user's
-- retrieval, which is the invariant exactly inverted. One bad row must never
-- poison the shared data.
--
-- There is deliberately no UPDATE or DELETE policy and no grant for either. An
-- update grant would let a user insert a quarantined row and then promote it,
-- which is the same hole through a second door.
-- ---------------------------------------------------------------------------
create policy places_insert_own_submission on public.places
  for insert to authenticated
  with check (
    source = 'user'
    and verification_tier = 'user_submitted'
    and submitted_by_user_id = (select auth.uid())
  );

grant insert on public.places to authenticated;

-- ---------------------------------------------------------------------------
-- known_areas — the barangays a user-added stop may sit in
--
-- Deliberately NOT origin_areas. That function returns only barangays holding
-- curated places, because an origin needs a coordinate and the only honest one
-- available is the centroid of real rows. A new place does not have that
-- problem: the user taps its coordinate on a map, so it brings its own.
--
-- Using origin_areas here would reject Duhat, Wakas and Batia — barangays
-- transit_fares knows routes to but that hold no curated place yet. Those are
-- precisely the places a missing stop is most worth adding.
--
-- Free text is the other wrong answer. fare_for matches barangay by exact
-- string, so "Poblacion" typed as "poblacion" silently makes every leg to that
-- stop unpriced forever, with nothing on screen explaining why. A closed list
-- is what keeps the fare join working.
--
-- KNOWN IMPURITY, inherited not introduced: transit_fares carries Marilao and
-- Balagtas, which are neighbouring municipalities rather than Bocaue
-- barangays, so they appear here too. D1 scopes the MVP to one municipality and
-- does not model that distinction; the fare to ride there is real either way.
-- ---------------------------------------------------------------------------
create function public.known_areas(p_city text)
returns table (
  area text,
  has_places boolean,
  has_fares boolean
)
language sql
stable
set search_path = ''
as $$
  with from_places as (
    select distinct p.barangay as area
    from public.places p
    where p.city = p_city
      and p.verification_tier = 'curated'
      and p.barangay is not null
  ),
  from_fares as (
    select f.from_area as area from public.transit_fares f
    union
    select f.to_area from public.transit_fares f
  )
  select
    a.area,
    exists (select 1 from from_places pl where pl.area = a.area),
    exists (select 1 from from_fares  fa where fa.area = a.area)
  from (
    select area from from_places
    union
    select area from from_fares
  ) a
  order by a.area;
$$;

comment on function public.known_areas is
  'Barangays a user-added stop may sit in: those with curated places, plus '
  'those transit_fares knows a route to. Wider than origin_areas, because a '
  'new place supplies its own coordinate and an origin cannot.';

-- ---------------------------------------------------------------------------
-- add_user_place — the only sanctioned way to write a place from a device
--
-- A function rather than a bare insert, for two reasons that the RLS policy
-- above cannot cover:
--
-- 1. places.slug is `not null unique`. A slug derived from the name will
--    collide the moment two users add "Aling Nena's", and a uniqueness error
--    on someone else's invisible row is impossible to explain. The server
--    generates it with a random suffix.
-- 2. The three quarantine columns are set here rather than trusted from the
--    client. The policy stays as the backstop — belt and braces, the same
--    doctrine retrieve_candidates already applies to verification_tier.
--
-- security invoker, so RLS still decides. This function is a convenience over
-- the policy, never a way around it.
-- ---------------------------------------------------------------------------
create function public.add_user_place(
  p_name text,
  p_category text,
  p_barangay text,
  p_lat double precision,
  p_lng double precision,
  p_price_min_php_cents integer default 0,
  p_price_max_php_cents integer default null
) returns uuid
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  city      text;
  new_slug  text;
  new_id    uuid;
begin
  if auth.uid() is null then
    raise exception 'add_user_place requires an authenticated user';
  end if;

  if coalesce(trim(p_name), '') = '' then
    raise exception 'add_user_place: a place needs a name';
  end if;

  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90
     or p_lng not between -180 and 180 then
    raise exception 'add_user_place: % , % is not a coordinate', p_lat, p_lng;
  end if;

  select pr.city into city from public.profiles pr where pr.id = auth.uid();
  city := coalesce(city, 'Bocaue');

  if not exists (
    select 1 from public.known_areas(city) k where k.area = p_barangay
  ) then
    raise exception
      'add_user_place: % is not an area this app knows a route to, so a leg to it could never be priced',
      coalesce(p_barangay, '(none)');
  end if;

  -- Readable, and unique without depending on the name being unique.
  new_slug := 'user-'
    || trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'))
    || '-'
    || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into public.places (
    slug, name, category, lat, lng, barangay, city,
    price_min_php_cents, price_max_php_cents,
    source, verification_tier, submitted_by_user_id
  ) values (
    new_slug, trim(p_name), coalesce(nullif(trim(p_category), ''), 'other'),
    p_lat, p_lng, p_barangay, city,
    greatest(coalesce(p_price_min_php_cents, 0), 0),
    p_price_max_php_cents,
    -- Not parameters. Invariant 5 is not a default the caller may override.
    'user', 'user_submitted', auth.uid()
  )
  returning id into new_id;

  return new_id;
end;
$$;

comment on function public.add_user_place is
  'Adds a quarantined, user-submitted place and returns its id. source, '
  'verification_tier and submitted_by_user_id are set here, never taken from '
  'the caller (invariant 5). Excluded from retrieval for everyone, including '
  'the submitter.';

revoke execute on function
  public.known_areas(text),
  public.add_user_place(text, text, text, double precision, double precision, integer, integer)
from public, anon;

grant execute on function
  public.known_areas(text),
  public.add_user_place(text, text, text, double precision, double precision, integer, integer)
to authenticated;
