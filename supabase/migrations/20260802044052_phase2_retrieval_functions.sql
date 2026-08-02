-- Phase 2 — retrieval and costing functions.
--
-- No new tables: this migration is entirely functions. They exist so that every
-- distance, fare and total is computed in Postgres from database rows, which is
-- CLAUDE.md invariant 3 taken literally — the device never does money
-- arithmetic, and neither will Gemini.
--
-- The split matters for Phase 3. `retrieve_candidates`, `retrieve_activities`,
-- `fare_for`, `haversine_m` and `is_open_at` are the durable half: the Edge
-- Function will call them unchanged to build its candidate set and to validate
-- and cost whatever the model returns. `build_simple_plan` is the throwaway
-- half — it is the crude non-AI composer that Gemini replaces. Keeping that seam
-- explicit now is the reason this phase exists before the AI one.
--
-- Every function is SECURITY INVOKER (the default) on purpose. RLS therefore
-- still decides which places the caller can see, so a user's own quarantined
-- submissions stay out of everyone else's retrieval (invariant 5) without a
-- single line of Dart. Each also pins `search_path = ''` and schema-qualifies
-- every reference, so nothing resolves through a caller-controlled path.
--
-- Grants follow the precedent in 20260731003449: EXECUTE is revoked from PUBLIC
-- (which Postgres grants by default) and given only to `authenticated`. Planning
-- requires a session, so `anon` gets nothing.

-- ---------------------------------------------------------------------------
-- haversine_m — great-circle distance in whole metres
--
-- Straight-line, not road distance. That is the honest thing to show when we
-- have no routing data: a walking figure computed from streets we have not
-- surveyed would be a more precise-looking lie. Phase 4's map makes the
-- straight-line nature visible to the user anyway.
-- ---------------------------------------------------------------------------
create or replace function public.haversine_m(
  lat1 double precision,
  lng1 double precision,
  lat2 double precision,
  lng2 double precision
) returns integer
language sql
immutable
parallel safe
set search_path = ''
as $$
  select round(
    2 * 6371000 * asin(
      sqrt(
        pow(sin(radians(lat2 - lat1) / 2), 2)
        + cos(radians(lat1)) * cos(radians(lat2))
          * pow(sin(radians(lng2 - lng1) / 2), 2)
      )
    )
  )::integer;
$$;

comment on function public.haversine_m is
  'Great-circle distance in metres. Straight-line, not road distance.';

-- ---------------------------------------------------------------------------
-- is_open_at — does this opening_hours blob cover this instant?
--
-- `opening_hours` is keyed by day, each day holding a list of ["HH:MM","HH:MM"]
-- ranges written by supabase/seed/csv_to_sql.mjs. Times are Asia/Manila wall
-- clock; the argument is UTC, per the storage convention.
--
-- A range whose closing time is earlier than its opening time wraps past
-- midnight, and is recorded against the day it OPENS: `fri 20:00-02:00` is
-- Friday night into Saturday morning. Amora plans evenings, so places that shut
-- at 1am are the interesting rows — reading them as "never open", which any
-- naive start <= t < end check does, would quietly delete the best half of the
-- catalogue. Hence the check looks at both today's ranges and yesterday's
-- wrapping ones.
--
-- A place with no recorded hours is never open. That is deliberate: retrieval
-- promises "currently open", and a blank hours column means we do not know. It
-- shows up as a missing place, which is a visible data gap rather than a false
-- promise.
--
-- STABLE rather than IMMUTABLE because the timezone conversion depends on the
-- timezone database, which can change under us.
-- ---------------------------------------------------------------------------
create or replace function public.is_open_at(
  hours jsonb,
  at_utc timestamptz
) returns boolean
language sql
stable
parallel safe
set search_path = ''
as $$
  with local_now as (
    select at_utc at time zone 'Asia/Manila' as ts
  ),
  parts as (
    select
      (array['sun','mon','tue','wed','thu','fri','sat'])[
        extract(dow from ts)::int + 1] as today,
      (array['sun','mon','tue','wed','thu','fri','sat'])[
        ((extract(dow from ts)::int + 6) % 7) + 1] as yesterday,
      (extract(hour from ts) * 60 + extract(minute from ts))::int as now_min
    from local_now
  ),
  ranges as (
    select
      p.now_min,
      d.is_today,
      split_part(r ->> 0, ':', 1)::int * 60
        + split_part(r ->> 0, ':', 2)::int as opens_min,
      split_part(r ->> 1, ':', 1)::int * 60
        + split_part(r ->> 1, ':', 2)::int as closes_min
    from parts p
    cross join lateral (
      values (p.today, true), (p.yesterday, false)
    ) as d(day, is_today)
    cross join lateral jsonb_array_elements(
      coalesce(hours -> d.day, '[]'::jsonb)
    ) as r
  )
  -- No rows at all (null or empty hours) means not open, hence the coalesce.
  select coalesce(bool_or(
    case
      when closes_min > opens_min
        -- Ordinary same-day range.
        then is_today and now_min >= opens_min and now_min < closes_min
      else
        -- Wraps past midnight: late on its own day, or early the next one.
        (is_today and now_min >= opens_min)
        or (not is_today and now_min < closes_min)
    end
  ), false)
  from ranges;
$$;

comment on function public.is_open_at is
  'True if opening_hours covers this UTC instant, in Asia/Manila wall clock. '
  'Handles ranges that wrap past midnight. Null hours means never open.';

-- ---------------------------------------------------------------------------
-- fare_for — what one leg between two barangays actually costs
--
-- Three cases, exactly one row returned in each:
--
--   under 800 m          walk, free, and never a table lookup (docs §7)
--   a recorded route     the cheapest non-walk mode we have for that pair
--   nothing recorded     fare_known = false
--
-- The lookup is deliberately symmetric. `transit_fares` is unique on
-- (from_area, to_area, mode) and the seed CSV records each route once, in one
-- direction, so an ordered lookup would silently miss half of them and report
-- perfectly ordinary routes as unknown.
--
-- The 'walk' and 'drive' modes are ignored when they appear in the table: a walk
-- is computed above, and a drive is not a fare a couple without a car pays.
--
-- Cheapest wins on ties because the entire product is "under ₱X". If a route has
-- both a ₱15 jeepney and a ₱25 tricycle, the jeepney is the honest default.
--
-- Nothing is ever estimated. No row means no row (D5, and the CLAUDE.md hard
-- rule against invented local data). Two places in the same barangay more than
-- 800 m apart will report unknown until an intra-barangay fare is recorded —
-- that gap is real, and it should be visible rather than papered over.
-- ---------------------------------------------------------------------------
create or replace function public.fare_for(
  p_from_area text,
  p_to_area text,
  p_distance_m integer
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

  select f.mode, f.fare_php_cents, true
  from (
    select t.mode, t.fare_php_cents
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

comment on function public.fare_for is
  'Cost of one leg. Walks under 800m are free; recorded routes match in either '
  'direction; anything else returns fare_known = false. Never estimates.';

-- ---------------------------------------------------------------------------
-- retrieve_candidates — the place half of docs §7 step 3
--
-- Filters on city, curated tier, budget, and actually being open at the
-- requested time, then applies the radius rule from docs §9: 3 km first, widened
-- to 5 km only when 3 km leaves too little to choose from. Six is the threshold
-- because the composer wants three stops and picking three from three is not
-- choosing.
--
-- There is deliberately no bounding-box pre-filter, which docs §7 sketches.
-- Haversine over a few hundred rows costs nothing measurable, while a box in
-- degrees is a standing correctness trap — a degree of longitude is not a degree
-- of latitude, and the fix is easy to get subtly wrong. Add one if the catalogue
-- ever reaches thousands of rows and a measurement says it matters.
--
-- `verification_tier = 'curated'` is belt and braces over the `places_read` RLS
-- policy: the policy already hides other users' submissions, and this makes sure
-- the caller's own submissions never reach anyone's plan either (invariant 5).
-- ---------------------------------------------------------------------------
create or replace function public.retrieve_candidates(
  p_city text,
  p_budget_php_cents integer,
  p_at timestamptz,
  p_origin_lat double precision,
  p_origin_lng double precision
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
      and p.price_min_php_cents <= p_budget_php_cents
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

comment on function public.retrieve_candidates is
  'Curated places in range, open at the given time, within budget. 3km radius '
  'widening to 5km when fewer than 6 candidates are near. Phase 3 reuses this.';

-- ---------------------------------------------------------------------------
-- retrieve_activities — the activity half of docs §7 step 3
--
-- `required_resource_ids <@ p_owned_resource_ids` is the whole point of the
-- Phase 1 resource picker: we never suggest a picnic to someone with no mat.
-- An activity requiring nothing has an empty array, which is contained by every
-- set, so it always qualifies.
-- ---------------------------------------------------------------------------
create or replace function public.retrieve_activities(
  p_budget_php_cents integer,
  p_owned_resource_ids uuid[] default '{}'
) returns table (
  activity_id uuid,
  slug text,
  title text,
  category text,
  min_budget_php_cents integer,
  max_budget_php_cents integer,
  duration_minutes integer,
  weather_dependent boolean,
  is_diy boolean
)
language sql
stable
set search_path = ''
as $$
  select
    a.id, a.slug, a.title, a.category,
    a.min_budget_php_cents, a.max_budget_php_cents, a.duration_minutes,
    a.weather_dependent, a.is_diy
  from public.activities a
  where a.min_budget_php_cents <= p_budget_php_cents
    and a.required_resource_ids <@ coalesce(p_owned_resource_ids, '{}'::uuid[])
  order by a.min_budget_php_cents, a.slug;
$$;

comment on function public.retrieve_activities is
  'Activities within budget whose required resources the user already owns.';

-- ---------------------------------------------------------------------------
-- build_simple_plan — the crude, deliberately dumb composer
--
-- Walks the candidates nearest-first and takes up to three, skipping any stop
-- that would push the running total past the budget. Nearest-first is not a
-- claim that proximity makes a good date; it is the simplest rule that produces
-- a costed, mappable, checkable itinerary, which is exactly what Phase 2 is for.
-- If the result reads as useful with real data in it, the data is good. If it
-- does not, no amount of Gemini will rescue it.
--
-- Gemini replaces THIS FUNCTION at Phase 3 and nothing else in this file.
--
-- An unpriced leg contributes 0 to the running budget check, because guessing
-- what it costs is the one thing we will not do. That makes the returned total a
-- floor rather than a promise, which is why `totals.is_complete` is returned
-- alongside it — the UI must say so out loud rather than present a short total
-- as a whole one.
-- ---------------------------------------------------------------------------
create or replace function public.build_simple_plan(
  p_city text,
  p_budget_php_cents integer,
  p_at timestamptz,
  p_origin_area text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_owned_resource_ids uuid[] default '{}'
) returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  max_stops constant integer := 3;

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

  candidate record;
  leg       record;
  leg_dist  integer;
begin
  for candidate in
    select *
    from public.retrieve_candidates(
      p_city, p_budget_php_cents, p_at, p_origin_lat, p_origin_lng)
  loop
    -- Reported even when no stop is affordable, so the UI can say "nothing
    -- within 5 km" rather than just "nothing".
    radius := coalesce(radius, candidate.radius_m);
    exit when seq >= max_stops;

    leg_dist := public.haversine_m(
      prev_lat, prev_lng, candidate.lat, candidate.lng);

    select * into leg
    from public.fare_for(prev_area, candidate.barangay, leg_dist);

    -- Too expensive together with everything before it: skip this one and try
    -- the next nearest rather than abandoning the plan.
    if places_cents + fares_cents
       + candidate.price_min_php_cents
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
      'price_min_php_cents', candidate.price_min_php_cents,
      'price_max_php_cents', candidate.price_max_php_cents,
      'distance_m', candidate.distance_m
    );

    places_cents := places_cents + candidate.price_min_php_cents;

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
          p_budget_php_cents, p_owned_resource_ids) a
      ),
      '[]'::jsonb
    )
  );
end;
$$;

comment on function public.build_simple_plan is
  'Phase 2 non-AI composer: up to 3 nearest affordable stops, costed legs and '
  'totals. Gemini replaces this function at Phase 3; the rest of this file '
  'survives.';

-- ---------------------------------------------------------------------------
-- origin_areas — the barangays a user can say they are starting from
--
-- Phase 2 asks for a barangay rather than reading GPS. Fares are keyed by
-- barangay, so a coordinate would have to be resolved to one before any leg
-- could be costed; asking directly skips a permission dialog, works indoors, and
-- is the granularity the fare data actually has. GPS arrives with the map in
-- Phase 4.
--
-- The coordinate returned is the centroid of the curated places in that
-- barangay — derived from real rows, never a number anyone typed from memory.
-- It is a rough centre, which is all a radius filter needs.
--
-- The consequence is that a barangay with no curated places cannot be an origin,
-- even when `transit_fares` knows routes to it. That is the correct failure: we
-- have no honest coordinate for it. It resolves itself as the catalogue grows.
-- ---------------------------------------------------------------------------
create or replace function public.origin_areas(p_city text)
returns table (
  area text,
  lat double precision,
  lng double precision,
  place_count integer
)
language sql
stable
set search_path = ''
as $$
  select
    p.barangay,
    avg(p.lat)::double precision,
    avg(p.lng)::double precision,
    count(*)::integer
  from public.places p
  where p.city = p_city
    and p.verification_tier = 'curated'
    and p.barangay is not null
  group by p.barangay
  order by p.barangay;
$$;

comment on function public.origin_areas is
  'Barangays that can serve as a plan origin, with the centroid of their '
  'curated places as a coordinate. Phase 2 stand-in for GPS.';

-- ---------------------------------------------------------------------------
-- Grants
--
-- Postgres grants EXECUTE to PUBLIC on new functions by default, which would put
-- every one of these on the REST API for anon. Revoke first, then grant to the
-- one role that should have them.
-- ---------------------------------------------------------------------------
revoke execute on function
  public.haversine_m(double precision, double precision, double precision, double precision),
  public.is_open_at(jsonb, timestamptz),
  public.fare_for(text, text, integer),
  public.retrieve_candidates(text, integer, timestamptz, double precision, double precision),
  public.retrieve_activities(integer, uuid[]),
  public.origin_areas(text),
  public.build_simple_plan(text, integer, timestamptz, text, double precision, double precision, uuid[])
from public, anon;

grant execute on function
  public.haversine_m(double precision, double precision, double precision, double precision),
  public.is_open_at(jsonb, timestamptz),
  public.fare_for(text, text, integer),
  public.retrieve_candidates(text, integer, timestamptz, double precision, double precision),
  public.retrieve_activities(integer, uuid[]),
  public.origin_areas(text),
  public.build_simple_plan(text, integer, timestamptz, text, double precision, double precision, uuid[])
to authenticated;
