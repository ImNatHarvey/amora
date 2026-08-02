-- Per-person pricing.
--
-- The bug this fixes: `places.price_min_php_cents` has always meant one person's
-- spend — the field checklist says "one drink, one serving" — but
-- `build_simple_plan` summed those and labelled the result the plan total. On
-- device that rendered "Total ₱200" against a ₱200 budget for a couple whose real
-- cost was up to double. No document stated the convention either way, so both
-- halves were individually defensible and jointly wrong.
--
-- Settled in docs/00-architecture.md §9: money is per person, totals multiply by
-- party size, and the user's budget always means the whole outing — ₱200 for the
-- date, not each. Per person wins over per couple because it is the only unit
-- that survives the persona expansion in §11; a per-couple price would need
-- re-collecting the day friends or families arrive.
--
-- Fares are the exception that proves the rule, and the reason this needs a
-- column rather than a constant: a jeepney charges every passenger, while a
-- tricycle special trip is one fare for the vehicle regardless of who is in it.
-- Multiplying both would overcharge every tricycle leg.

-- ---------------------------------------------------------------------------
-- transit_fares.is_per_person
--
-- Defaults true because jeepney and bus — the modes where the distinction is
-- unambiguous — are per passenger. The existing tricycle rows are left at the
-- default deliberately rather than guessed at: which rate was recorded is a
-- question only the person who rode it can answer, and inventing the answer is
-- exactly what D5 forbids. They are flagged for review in the seed CSV instead.
-- ---------------------------------------------------------------------------
alter table public.transit_fares
  add column is_per_person boolean not null default true;

comment on column public.transit_fares.is_per_person is
  'True when each passenger pays (jeepney, bus). False for a tricycle special '
  'trip, which is one fare for the vehicle. Decides whether party size '
  'multiplies this fare.';

-- ---------------------------------------------------------------------------
-- places.verified_on
--
-- `verified_at` is set to now() by the seed importer, so it records when the CSV
-- was imported rather than when someone stood at the door. Those differ by weeks
-- once collection and import are separate acts, which makes it useless as the
-- staleness signal that §10.5 needs. `verified_on` is the real visit date,
-- supplied by the CSV.
-- ---------------------------------------------------------------------------
alter table public.places
  add column verified_on date;

comment on column public.places.verified_on is
  'The date a person actually stood at this place. Distinct from verified_at, '
  'which records when the row was imported.';

-- ---------------------------------------------------------------------------
-- Drop the superseded signatures BEFORE creating the new ones.
--
-- Not housekeeping — ordering. Each function below gains a parameter, so
-- `create or replace` makes an overload rather than replacing, and while two
-- overloads coexist every `comment on function` and `grant` is ambiguous
-- ("function name is not unique"). Dropping first also guarantees nothing can
-- keep calling the version that silently ignores party size.
--
-- Postgres does not track function-to-function dependencies in bodies, so
-- dropping these while the old build_simple_plan still exists is safe; it is
-- dropped in the same breath anyway.
-- ---------------------------------------------------------------------------
drop function if exists public.build_simple_plan(
  text, integer, timestamptz, text, double precision, double precision, uuid[]);
drop function if exists public.retrieve_candidates(
  text, integer, timestamptz, double precision, double precision);
drop function if exists public.fare_for(text, text, integer);

-- ---------------------------------------------------------------------------
-- fare_for — multiply only what is charged per head
-- ---------------------------------------------------------------------------
create or replace function public.fare_for(
  p_from_area text,
  p_to_area text,
  p_distance_m integer,
  p_party_size integer default 1
) returns table (
  mode text,
  fare_php_cents integer,
  fare_known boolean
)
language sql
stable
parallel safe
set search_path = ''
as $$
  select 'walk'::text, 0, true
  where p_distance_m < 800

  union all

  select
    f.mode,
    -- The whole point of is_per_person: a jeepney bills each head, a tricycle
    -- special trip bills the vehicle once.
    case when f.is_per_person
      then f.fare_php_cents * greatest(p_party_size, 1)
      else f.fare_php_cents
    end,
    true
  from (
    select t.mode, t.fare_php_cents, t.is_per_person
    from public.transit_fares t
    where t.mode not in ('walk', 'drive')
      and ((t.from_area = p_from_area and t.to_area = p_to_area)
        or (t.from_area = p_to_area   and t.to_area = p_from_area))
    order by t.fare_php_cents
    limit 1
  ) f
  where p_distance_m >= 800

  union all

  select null::text, null::integer, false
  where p_distance_m >= 800
    and not exists (
      select 1
      from public.transit_fares t
      where t.mode not in ('walk', 'drive')
        and ((t.from_area = p_from_area and t.to_area = p_to_area)
          or (t.from_area = p_to_area   and t.to_area = p_from_area))
    );
$$;

comment on function public.fare_for(text, text, integer, integer) is
  'Cost of one leg for the whole party. Walks under 800m are free; recorded '
  'routes match in either direction; per-passenger modes multiply by party '
  'size. Never estimates.';

-- ---------------------------------------------------------------------------
-- retrieve_candidates — budget is for the party, prices are per person
--
-- The budget filter has to compare like with like. A ₱200 budget for two people
-- can afford a ₱100-per-head café, so the per-person price is compared against
-- the per-person share of the budget, not against the whole thing.
-- ---------------------------------------------------------------------------
create or replace function public.retrieve_candidates(
  p_city text,
  p_budget_php_cents integer,
  p_at timestamptz,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_party_size integer default 2
) returns table (
  place_id uuid,
  slug text,
  name text,
  category text,
  barangay text,
  lat double precision,
  lng double precision,
  opening_hours jsonb,
  price_min_php_cents integer,
  price_max_php_cents integer,
  indoor boolean,
  distance_m integer,
  radius_m integer
)
language sql
stable
set search_path = ''
as $$
  with scored as (
    select
      p.id, p.slug, p.name, p.category, p.barangay, p.lat, p.lng,
      p.opening_hours, p.price_min_php_cents, p.price_max_php_cents, p.indoor,
      public.haversine_m(p_origin_lat, p_origin_lng, p.lat, p.lng) as distance_m
    from public.places p
    where p.city = p_city
      and p.verification_tier = 'curated'
      -- Per-person price against the per-person share of the budget.
      and p.price_min_php_cents
          <= (p_budget_php_cents / greatest(p_party_size, 1))
      and public.is_open_at(p.opening_hours, p_at)
  ),
  chosen_radius as (
    select case
      when count(*) filter (where distance_m <= 3000) >= 6 then 3000
      else 5000
    end as m
    from scored
  )
  select
    s.id, s.slug, s.name, s.category, s.barangay, s.lat, s.lng,
    s.opening_hours, s.price_min_php_cents, s.price_max_php_cents, s.indoor,
    s.distance_m, r.m
  from scored s
  cross join chosen_radius r
  where s.distance_m <= r.m
  order by s.distance_m, s.slug;
$$;

comment on function public.retrieve_candidates(text, integer, timestamptz, double precision, double precision, integer) is
  'Curated places in range, open at the given time, affordable at the '
  'per-person share of the budget. 3km radius widening to 5km when fewer than 6 '
  'candidates are near. Phase 3 reuses this.';

-- ---------------------------------------------------------------------------
-- build_simple_plan — totals are what the party actually pays
-- ---------------------------------------------------------------------------
create or replace function public.build_simple_plan(
  p_city text,
  p_budget_php_cents integer,
  p_at timestamptz,
  p_origin_area text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_owned_resource_ids uuid[] default '{}',
  p_party_size integer default 2
) returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  max_stops constant integer := 3;
  party constant integer := greatest(coalesce(p_party_size, 2), 1);

  stops        jsonb := '[]'::jsonb;
  legs         jsonb := '[]'::jsonb;
  places_cents integer := 0;
  fares_cents  integer := 0;
  unpriced     integer := 0;
  seq          integer := 0;
  radius       integer := null;

  prev_area text := p_origin_area;
  prev_lat  double precision := p_origin_lat;
  prev_lng  double precision := p_origin_lng;
  prev_name text := p_origin_area;

  candidate  record;
  leg        record;
  leg_dist   integer;
  stop_cents integer;
begin
  for candidate in
    select *
    from public.retrieve_candidates(
      p_city, p_budget_php_cents, p_at, p_origin_lat, p_origin_lng, party)
  loop
    radius := coalesce(radius, candidate.radius_m);
    exit when seq >= max_stops;

    leg_dist := public.haversine_m(
      prev_lat, prev_lng, candidate.lat, candidate.lng);

    -- fare_for already applies party size to per-passenger modes.
    select * into leg
    from public.fare_for(prev_area, candidate.barangay, leg_dist, party);

    -- The stored price is one person's; the party pays it once each.
    stop_cents := candidate.price_min_php_cents * party;

    if places_cents + fares_cents
       + stop_cents
       + coalesce(leg.fare_php_cents, 0) > p_budget_php_cents then
      continue;
    end if;

    seq := seq + 1;

    legs := legs || jsonb_build_object(
      'seq', seq,
      'from_name', prev_name,
      'to_name', candidate.name,
      'mode', leg.mode,
      'distance_m', leg_dist,
      'fare_php_cents', leg.fare_php_cents,
      'fare_known', leg.fare_known
    );

    stops := stops || jsonb_build_object(
      'seq', seq,
      'place_id', candidate.place_id,
      'slug', candidate.slug,
      'name', candidate.name,
      'category', candidate.category,
      'barangay', candidate.barangay,
      'lat', candidate.lat,
      'lng', candidate.lng,
      'opening_hours', candidate.opening_hours,
      -- Per person, as stored, so the UI can show a per-head price beside a
      -- party total without doing arithmetic of its own (invariant 3).
      'price_min_php_cents', candidate.price_min_php_cents,
      'price_max_php_cents', candidate.price_max_php_cents,
      'party_price_php_cents', stop_cents,
      'distance_m', candidate.distance_m
    );

    places_cents := places_cents + stop_cents;

    if leg.fare_known then
      fares_cents := fares_cents + leg.fare_php_cents;
    else
      unpriced := unpriced + 1;
    end if;

    prev_area := candidate.barangay;
    prev_lat  := candidate.lat;
    prev_lng  := candidate.lng;
    prev_name := candidate.name;
  end loop;

  return jsonb_build_object(
    'planned_for', p_at,
    'budget_php_cents', p_budget_php_cents,
    'party_size', party,
    'radius_m', radius,
    'origin', jsonb_build_object(
      'area', p_origin_area, 'lat', p_origin_lat, 'lng', p_origin_lng),
    'stops', stops,
    'legs', legs,
    'totals', jsonb_build_object(
      'places_php_cents', places_cents,
      'fares_php_cents', fares_cents,
      'total_php_cents', places_cents + fares_cents,
      'unpriced_legs', unpriced,
      'is_complete', unpriced = 0
    ),
    'candidate_activities', coalesce(
      (
        select jsonb_agg(to_jsonb(a) order by a.min_budget_php_cents, a.slug)
        from public.retrieve_activities(
          p_budget_php_cents / party, p_owned_resource_ids) a
      ),
      '[]'::jsonb
    )
  );
end;
$$;

comment on function public.build_simple_plan(text, integer, timestamptz, text, double precision, double precision, uuid[], integer) is
  'Phase 2 non-AI composer: up to 3 nearest stops the party can afford, costed '
  'legs and party totals. Gemini replaces this function at Phase 3.';

-- ---------------------------------------------------------------------------
-- Grants. The old signatures are gone (the parameter lists changed), so the new
-- ones need their own revoke/grant pair.
-- ---------------------------------------------------------------------------
revoke execute on function
  public.fare_for(text, text, integer, integer),
  public.retrieve_candidates(text, integer, timestamptz, double precision, double precision, integer),
  public.build_simple_plan(text, integer, timestamptz, text, double precision, double precision, uuid[], integer)
from public, anon;

grant execute on function
  public.fare_for(text, text, integer, integer),
  public.retrieve_candidates(text, integer, timestamptz, double precision, double precision, integer),
  public.build_simple_plan(text, integer, timestamptz, text, double precision, double precision, uuid[], integer)
to authenticated;
