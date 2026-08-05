-- cost_generated_plan — invariants 2 and 3, in one place.
--
-- The model returns a sequence of {place_id, activity_id, start_time,
-- duration_minutes, note} and nothing else. It never returns a price, a fare,
-- a distance or a total, because it is not allowed to do arithmetic on money
-- (invariant 3) and it is not allowed to name a place we did not give it
-- (invariant 1).
--
-- This function does two jobs the Edge Function must not do in TypeScript:
--
-- 1. VALIDATE. Every place_id and activity_id must be inside the candidate set.
--    Crucially it *recomputes* that set from the same constraints rather than
--    trusting a list handed in alongside the model output. What the model was
--    given and what its answer is checked against are then the same rows by
--    construction, which is the whole argument in §4a. A tampered or stale
--    candidate list cannot widen what is accepted.
--
-- 2. COST. Distances, modes, fares and totals are computed here, next to the
--    rows they sum, using the same haversine_m and fare_for the Phase 2 screen
--    exercises. One implementation, so the app and the model can never be shown
--    two different numbers for the same plan.
--
-- It returns rather than raises on invalid input, because §7 step 5 requires
-- one corrective retry and the retry message has to name the offending IDs.
-- A raise would lose them.
--
-- Returns the same jsonb shape build_simple_plan returns, plus `valid`,
-- `invalid_place_ids`, `invalid_activity_ids` and `over_budget`, so the Flutter
-- side can render a generated plan through the model it already has.
create or replace function public.cost_generated_plan(
  p_city text,
  p_budget_php_cents integer,
  p_at timestamptz,
  p_origin_area text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_stops jsonb,
  p_owned_resource_ids uuid[] default '{}',
  p_party_size integer default 2
) returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  party constant integer := greatest(coalesce(p_party_size, 2), 1);

  candidate_ids uuid[];
  activity_ids  uuid[];
  radius        integer;

  bad_places     uuid[];
  bad_activities uuid[];

  stops        jsonb := '[]'::jsonb;
  legs         jsonb := '[]'::jsonb;
  places_cents integer := 0;
  fares_cents  integer := 0;
  unpriced     integer := 0;
  seq          integer := 0;

  prev_area text := p_origin_area;
  prev_lat  double precision := p_origin_lat;
  prev_lng  double precision := p_origin_lng;
  prev_name text := p_origin_area;

  stop      jsonb;
  place     record;
  leg       record;
  leg_dist  integer;
  stop_cents integer;
begin
  -- The candidate set, recomputed. Never passed in.
  select array_agg(c.place_id), min(c.radius_m)
    into candidate_ids, radius
  from public.retrieve_candidates(
    p_city, p_budget_php_cents, p_at, p_origin_lat, p_origin_lng, party) c;

  select array_agg(a.activity_id)
    into activity_ids
  from public.retrieve_activities(
    p_budget_php_cents / party, p_owned_resource_ids) a;

  candidate_ids := coalesce(candidate_ids, '{}'::uuid[]);
  activity_ids  := coalesce(activity_ids, '{}'::uuid[]);

  -- Anything the model invented, collected rather than thrown, so the caller
  -- can put the offending IDs into its one corrective retry.
  select
    coalesce(array_agg(distinct pid) filter (
      where pid is not null and not (pid = any (candidate_ids))), '{}'::uuid[]),
    coalesce(array_agg(distinct aid) filter (
      where aid is not null and not (aid = any (activity_ids))), '{}'::uuid[])
    into bad_places, bad_activities
  from (
    select
      nullif(s ->> 'place_id', '')::uuid    as pid,
      nullif(s ->> 'activity_id', '')::uuid as aid
    from jsonb_array_elements(coalesce(p_stops, '[]'::jsonb)) s
  ) parsed;

  if array_length(bad_places, 1) is not null
     or array_length(bad_activities, 1) is not null then
    return jsonb_build_object(
      'valid', false,
      'invalid_place_ids', to_jsonb(bad_places),
      'invalid_activity_ids', to_jsonb(bad_activities),
      'candidate_place_ids', to_jsonb(candidate_ids),
      'candidate_activity_ids', to_jsonb(activity_ids)
    );
  end if;

  -- Valid. Cost it, in the order the model chose.
  for stop in select value from jsonb_array_elements(coalesce(p_stops, '[]'::jsonb))
  loop
    select p.id, p.name, p.category, p.barangay, p.lat, p.lng, p.opening_hours,
           p.price_min_php_cents, p.price_max_php_cents
      into place
    from public.places p
    where p.id = (stop ->> 'place_id')::uuid;

    continue when place.id is null;

    seq := seq + 1;

    leg_dist := public.haversine_m(prev_lat, prev_lng, place.lat, place.lng);

    select * into leg
    from public.fare_for(prev_area, place.barangay, leg_dist, party);

    -- Per-person price, paid once by each member of the party (§9).
    stop_cents := coalesce(place.price_min_php_cents, 0) * party;

    legs := legs || jsonb_build_object(
      'seq', seq,
      'from_name', prev_name,
      'to_name', place.name,
      'mode', leg.mode,
      'distance_m', leg_dist,
      'fare_php_cents', leg.fare_php_cents,
      'fare_known', leg.fare_known
    );

    stops := stops || jsonb_build_object(
      'seq', seq,
      'place_id', place.id,
      'activity_id', nullif(stop ->> 'activity_id', '')::uuid,
      'name', place.name,
      'category', place.category,
      'barangay', place.barangay,
      'lat', place.lat,
      'lng', place.lng,
      'opening_hours', place.opening_hours,
      'price_min_php_cents', place.price_min_php_cents,
      'price_max_php_cents', place.price_max_php_cents,
      'party_price_php_cents', stop_cents,
      'distance_m', public.haversine_m(
        p_origin_lat, p_origin_lng, place.lat, place.lng),
      'start_time', stop ->> 'start_time',
      'duration_minutes', nullif(stop ->> 'duration_minutes', '')::integer,
      -- The model's own words about why this stop, which is the one thing it
      -- is genuinely allowed to author. It carries no facts we did not give it.
      'note', stop ->> 'note'
    );

    places_cents := places_cents + stop_cents;

    if leg.fare_known then
      fares_cents := fares_cents + leg.fare_php_cents;
    else
      unpriced := unpriced + 1;
    end if;

    prev_area := place.barangay;
    prev_lat  := place.lat;
    prev_lng  := place.lng;
    prev_name := place.name;
  end loop;

  return jsonb_build_object(
    'valid', true,
    'invalid_place_ids', '[]'::jsonb,
    'invalid_activity_ids', '[]'::jsonb,
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
    -- Not a rejection. A plan the user cannot afford is a real answer and the
    -- UI has a colour and an icon for it; silently dropping stops to fit would
    -- be the composer lying about what it found.
    'over_budget', (places_cents + fares_cents) > p_budget_php_cents
  );
end;
$$;

comment on function public.cost_generated_plan(
  text, integer, timestamptz, text, double precision, double precision, jsonb, uuid[], integer) is
  'Validates a model-produced stop sequence against a freshly recomputed '
  'candidate set (invariant 2) and costs it server-side (invariant 3). Returns '
  'valid=false with the offending IDs rather than raising, so the caller can '
  'issue its one corrective retry.';

-- Not granted to authenticated. The Edge Function calls this with the service
-- role: letting a device validate its own generated plan would put both halves
-- of the trust boundary on the same side of it.
revoke execute on function public.cost_generated_plan(
  text, integer, timestamptz, text, double precision, double precision, jsonb, uuid[], integer)
from public, anon, authenticated;
