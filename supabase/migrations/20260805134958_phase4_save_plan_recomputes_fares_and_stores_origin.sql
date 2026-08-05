-- save_plan trusted the client's fares. Caught by its own invariant-3 test:
-- a payload claiming a ₱9,999.99 milk tea was correctly ignored, and a payload
-- claiming an ₱8,888.88 walk was stored verbatim.
--
-- Invariant 3 is "all costs, FARES, and totals are computed server-side from
-- database rows". Half of that was implemented. A fare handed in by a device is
-- not computed server-side no matter how plausible it looks.
--
-- The fix goes further than patching the read: save_plan now ignores the
-- payload's `legs` array entirely and derives every leg itself from the place
-- coordinates it just resolved, using the same haversine_m and fare_for the
-- composers use. Fewer inputs to trust is better than more inputs to validate.
--
-- The origin is the one thing that genuinely comes from the user — which
-- barangay they are starting from — so it is validated against origin_areas
-- rather than taken on faith, and its coordinate is that function's centroid of
-- real rows. A barangay we have no places in cannot be an origin, which is the
-- same rule retrieval already applies.

-- ---------------------------------------------------------------------------
-- plans.origin_area
--
-- Needed to redraw a reopened plan: the first leg runs from the origin, not
-- from a stop, and without this the origin is unrecoverable. read_plan was
-- guessing it from the first stop's barangay, which is wrong whenever someone
-- starts in one barangay and the nearest affordable place is in another.
-- ---------------------------------------------------------------------------
alter table public.plans
  add column if not exists origin_area text;

comment on column public.plans.origin_area is
  'The barangay the plan starts from. Validated against origin_areas at save '
  'time; its coordinate is that function''s centroid of curated places, never '
  'a figure supplied by the device.';

create or replace function public.save_plan(
  p_payload jsonb,
  p_title text default null
) returns uuid
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  new_plan_id uuid;
  party        integer;
  budget       integer;
  planned_for  timestamptz;
  origin_area  text;
  origin_lat   double precision;
  origin_lng   double precision;
  city         text;

  stop      jsonb;
  seq_no    integer;
  place_row record;
  item_id   uuid;
  item_ids  uuid[] := '{}';

  prev_area text;
  prev_lat  double precision;
  prev_lng  double precision;
  leg_dist  integer;
  leg       record;
begin
  if auth.uid() is null then
    raise exception 'save_plan requires an authenticated user';
  end if;

  party       := greatest(coalesce((p_payload ->> 'party_size')::integer, 2), 1);
  budget      := coalesce((p_payload ->> 'budget_php_cents')::integer, 0);
  planned_for := coalesce((p_payload ->> 'planned_for')::timestamptz, now());
  origin_area := nullif(p_payload -> 'origin' ->> 'area', '');
  city        := coalesce((select p.city from public.profiles pr
                           join public.places p on p.city = pr.city
                           where pr.id = auth.uid() limit 1), 'Bocaue');

  -- The origin's coordinate comes from origin_areas, never from the payload.
  select o.lat, o.lng into origin_lat, origin_lng
  from public.origin_areas(city) o
  where o.area = origin_area;

  if origin_lat is null then
    raise exception
      'save_plan: % is not an area with curated places, so it cannot be a plan origin',
      coalesce(origin_area, '(none)');
  end if;

  insert into public.plans (
    user_id, title, budget_php_cents, party_size, planned_for, status, origin,
    generated_by_model, origin_area
  ) values (
    auth.uid(),
    coalesce(p_title, p_payload ->> 'title'),
    budget, party, planned_for, 'draft', 'generated',
    p_payload ->> 'generated_by_model',
    origin_area
  )
  returning id into new_plan_id;

  prev_area := origin_area;
  prev_lat  := origin_lat;
  prev_lng  := origin_lng;

  seq_no := 0;
  for stop in select value from jsonb_array_elements(coalesce(p_payload -> 'stops', '[]'::jsonb))
  loop
    select p.id, p.lat, p.lng, p.barangay, p.price_min_php_cents
      into place_row
    from public.places p
    where p.id = (stop ->> 'place_id')::uuid;

    -- A stop naming a place that no longer exists is skipped rather than
    -- stored as a hole. Saving is not the moment to invent a row.
    continue when place_row.id is null;

    insert into public.plan_items (
      plan_id, seq, activity_id, place_id, start_time, duration_minutes,
      est_cost_php_cents, note
    ) values (
      new_plan_id, seq_no,
      nullif(stop ->> 'activity_id', '')::uuid,
      place_row.id,
      nullif(stop ->> 'start_time', '')::timestamptz,
      nullif(stop ->> 'duration_minutes', '')::integer,
      -- Invariant 3: recomputed, never the payload's figure.
      coalesce(place_row.price_min_php_cents, 0) * party,
      stop ->> 'note'
    )
    returning id into item_id;

    -- The leg INTO this stop, derived rather than read. The payload's `legs`
    -- array is ignored completely.
    leg_dist := public.haversine_m(prev_lat, prev_lng, place_row.lat, place_row.lng);
    select * into leg
    from public.fare_for(prev_area, place_row.barangay, leg_dist, party);

    insert into public.plan_legs (
      plan_id, from_item_id, to_item_id, seq, mode, distance_m, fare_php_cents
    ) values (
      new_plan_id,
      case when seq_no = 0 then null else item_ids[seq_no] end,
      item_id,
      seq_no,
      leg.mode,
      leg_dist,
      -- Null when no fare was recorded. Null is a fact here, not a gap: it is
      -- what stops an unpriced leg being silently counted as free.
      case when leg.fare_known then leg.fare_php_cents else null end
    );

    item_ids := item_ids || item_id;
    prev_area := place_row.barangay;
    prev_lat  := place_row.lat;
    prev_lng  := place_row.lng;
    seq_no := seq_no + 1;
  end loop;

  return new_plan_id;
end;
$$;

comment on function public.save_plan(jsonb, text) is
  'Writes a costed plan to plans/plan_items/plan_legs and returns its id. Takes '
  'place ids, order and the model''s notes from the payload; recomputes every '
  'distance, fare and peso from the database (invariant 3). The payload''s '
  'legs array is ignored entirely.';

-- ---------------------------------------------------------------------------
-- read_plan — now returns the real origin, with its coordinate.
-- ---------------------------------------------------------------------------
create or replace function public.read_plan(p_plan_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with plan as (
    select * from public.plans where id = p_plan_id
  ),
  origin as (
    select o.area, o.lat, o.lng
    from plan
    cross join lateral public.origin_areas(
      coalesce((select pr.city from public.profiles pr where pr.id = plan.user_id), 'Bocaue')) o
    where o.area = plan.origin_area
  ),
  stops as (
    select
      i.seq,
      jsonb_build_object(
        'seq', i.seq + 1,
        'place_id', p.id, 'slug', p.slug, 'activity_id', i.activity_id,
        'name', p.name, 'category', p.category, 'barangay', p.barangay,
        'lat', p.lat, 'lng', p.lng, 'opening_hours', p.opening_hours,
        'price_min_php_cents', p.price_min_php_cents,
        'price_max_php_cents', p.price_max_php_cents,
        'party_price_php_cents', i.est_cost_php_cents,
        'distance_m', coalesce(public.haversine_m(
          (select lat from origin), (select lng from origin), p.lat, p.lng), 0),
        'start_time', i.start_time,
        'duration_minutes', i.duration_minutes,
        'note', i.note
      ) as stop,
      i.est_cost_php_cents
    from public.plan_items i
    join plan on plan.id = i.plan_id
    join public.places p on p.id = i.place_id
  ),
  legs as (
    select
      l.seq,
      jsonb_build_object(
        'seq', l.seq + 1,
        'from_name', coalesce(fp.name, (select area from origin), 'origin'),
        'to_name', tp.name,
        'mode', l.mode,
        'distance_m', coalesce(l.distance_m, 0),
        'fare_php_cents', l.fare_php_cents,
        'fare_known', l.fare_php_cents is not null
      ) as leg,
      l.fare_php_cents
    from public.plan_legs l
    join plan on plan.id = l.plan_id
    left join public.plan_items fi on fi.id = l.from_item_id
    left join public.places fp on fp.id = fi.place_id
    left join public.plan_items ti on ti.id = l.to_item_id
    left join public.places tp on tp.id = ti.place_id
  )
  select case when (select count(*) from plan) = 0 then null else
    jsonb_build_object(
      'plan_id', (select id from plan),
      'title', (select title from plan),
      'planned_for', (select planned_for from plan),
      'budget_php_cents', (select budget_php_cents from plan),
      'party_size', (select party_size from plan),
      'status', (select status from plan),
      'generated_by_model', (select generated_by_model from plan),
      'radius_m', null,
      'origin', jsonb_build_object(
        'area', (select plan.origin_area from plan),
        'lat', (select lat from origin),
        'lng', (select lng from origin)),
      'stops', coalesce((select jsonb_agg(stop order by seq) from stops), '[]'::jsonb),
      'legs', coalesce((select jsonb_agg(leg order by seq) from legs), '[]'::jsonb),
      'totals', jsonb_build_object(
        'places_php_cents', coalesce((select sum(est_cost_php_cents) from stops), 0),
        'fares_php_cents', coalesce((select sum(fare_php_cents) from legs), 0),
        'total_php_cents',
          coalesce((select sum(est_cost_php_cents) from stops), 0)
          + coalesce((select sum(fare_php_cents) from legs), 0),
        'unpriced_legs', (select count(*) from legs where fare_php_cents is null),
        'is_complete', (select count(*) from legs where fare_php_cents is null) = 0
      ),
      'candidate_activities', '[]'::jsonb
    )
  end;
$$;

revoke execute on function public.save_plan(jsonb, text) from public, anon;
revoke execute on function public.read_plan(uuid) from public, anon;
grant execute on function public.save_plan(jsonb, text) to authenticated;
grant execute on function public.read_plan(uuid) to authenticated;
