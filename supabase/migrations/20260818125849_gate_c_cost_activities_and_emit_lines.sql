-- Gate C, part 1: activity budgets were in no plan total.
--
-- cost_generated_plan stored `activity_id` on each stop and never added the
-- activity's budget to anything. "Make a scrapbook together" — ₱100–₱400 per
-- person — cost ₱0 in the plan it was attached to, and `over_budget` was
-- derived from that same understated figure, so a plan could be presented as
-- affordable when it was not.
--
-- This is invariant 3's failure mode exactly: the server is the only thing
-- allowed to do arithmetic on money, so anything it forgets to add is money
-- nobody adds.
--
-- Part 2: `totals.lines` — the breakdown, computed here rather than rendered
-- from parts. Same reason. The UI sums nothing; it prints what this returns.
--
-- The activity's MINIMUM budget is used, matching what places do with
-- price_min_php_cents. A total in this app is a floor, and `is_complete`
-- already tells the UI when to say so.
--
-- Per person, multiplied by party_size (§9), exactly like a place price. Two
-- people making one scrapbook is arguably one set of materials — but the same
-- is true of one tricycle, which is why transit_fares has is_per_person and
-- activities does not. Recorded as a known simplification rather than a
-- discovery: if it matters, activities needs that column too, and that is a
-- schema change with a data-collection cost.

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

  stops          jsonb := '[]'::jsonb;
  legs           jsonb := '[]'::jsonb;
  places_cents   integer := 0;
  fares_cents    integer := 0;
  activity_cents integer := 0;
  unpriced       integer := 0;
  seq            integer := 0;

  -- The four non-fare lines. Kept as separate counters rather than a jsonb
  -- accumulator so the arithmetic stays integer the whole way; money is never
  -- a float in this codebase and jsonb would invite one.
  line_food       integer := 0;
  line_gifts      integer := 0;
  line_activities integer := 0;
  line_materials  integer := 0;

  prev_area text := p_origin_area;
  prev_lat  double precision := p_origin_lat;
  prev_lng  double precision := p_origin_lng;
  prev_name text := p_origin_area;

  stop       jsonb;
  place      record;
  act        record;
  leg        record;
  leg_dist   integer;
  stop_cents integer;
  act_cents  integer;
  place_line text;
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
    select p.id, p.slug, p.name, p.category, p.barangay, p.lat, p.lng,
           p.opening_hours, p.price_min_php_cents, p.price_max_php_cents
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

    -- The activity attached to this stop, if the model chose one. Validated
    -- above, so a row is guaranteed to exist when the id is non-null.
    act_cents := 0;
    if nullif(stop ->> 'activity_id', '') is not null then
      select a.min_budget_php_cents, a.is_diy
        into act
      from public.activities a
      where a.id = (stop ->> 'activity_id')::uuid;

      act_cents := coalesce(act.min_budget_php_cents, 0) * party;

      -- A DIY activity's budget IS its materials. That is the whole difference
      -- between the two lines, and it is why is_diy decides rather than
      -- category: "cook a meal together" buys ingredients, "cafe hopping" buys
      -- an experience.
      if act.is_diy then
        line_materials := line_materials + act_cents;
      else
        line_activities := line_activities + act_cents;
      end if;
    end if;

    place_line := public.cost_line_for_place(place.category);
    if place_line = 'food' then
      line_food := line_food + stop_cents;
    elsif place_line = 'gifts' then
      line_gifts := line_gifts + stop_cents;
    else
      line_activities := line_activities + stop_cents;
    end if;

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
      'slug', place.slug,
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
      -- What the attached activity adds, for the party. Zero when there is no
      -- activity, so the field always exists and the UI never has to decide
      -- what a missing key means.
      'activity_price_php_cents', act_cents,
      'distance_m', public.haversine_m(
        p_origin_lat, p_origin_lng, place.lat, place.lng),
      'start_time', stop ->> 'start_time',
      'duration_minutes', nullif(stop ->> 'duration_minutes', '')::integer,
      -- The model's own words about why this stop, which is the one thing it
      -- is genuinely allowed to author. It carries no facts we did not give it.
      'note', stop ->> 'note'
    );

    places_cents   := places_cents + stop_cents;
    activity_cents := activity_cents + act_cents;

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
      -- New, and the bug this migration exists for. Was silently absent from
      -- every total.
      'activities_php_cents', activity_cents,
      'total_php_cents', places_cents + fares_cents + activity_cents,
      'unpriced_legs', unpriced,
      'is_complete', unpriced = 0,
      -- The breakdown, in render order. Every peso in total_php_cents lands on
      -- exactly one of these five, which is the property worth testing: the
      -- lines must sum to the total or the breakdown is decoration.
      'lines', jsonb_build_object(
        'fares', fares_cents,
        'food', line_food,
        'materials', line_materials,
        'activities', line_activities,
        'gifts', line_gifts
      )
    ),
    'over_budget',
      (places_cents + fares_cents + activity_cents) > p_budget_php_cents
  );
end;
$$;

comment on function public.cost_generated_plan(
  text, integer, timestamptz, text, double precision, double precision, jsonb, uuid[], integer) is
  'Validates a model-produced stop sequence against a freshly recomputed '
  'candidate set (invariant 2) and costs it server-side (invariant 3). Totals '
  'include attached activity budgets, per person and multiplied by party_size; '
  'totals.lines breaks the total into fares, food, materials, activities and '
  'gifts, and those five sum to total_php_cents. Returns valid=false with the '
  'offending IDs rather than raising, so the caller can issue its one '
  'corrective retry.';
