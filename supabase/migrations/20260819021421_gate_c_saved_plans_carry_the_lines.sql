-- Gate C — a saved plan returns the same five lines a generated one did.
--
-- Until now only cost_generated_plan emitted `totals.lines`. read_plan did not,
-- so saving a plan and reopening it silently changed the payload shape: the
-- breakdown the user was looking at when they tapped Save did not come back.
-- Two composers already have to agree field-for-field (that is why
-- build_simple_plan emits lines it can never populate); the saved-plan path is
-- the third reader of the same contract and was left out.
--
-- Materials money is STORED rather than recomputed at read time.
-- `write_plan_stops` is the one recompute path — invariant 3 — and it already
-- derives every peso from the database at write time. Recomputing the activity
-- budget again in read_plan would give the rule two homes, and a later change
-- to `activities.min_budget_php_cents` would then retroactively rewrite the
-- cost of an outing somebody has already had.
--
-- The place lines ARE derived at read time, from `cost_line_for_place`, because
-- a place's category is a property of the place and not of the plan. Correcting
-- a miscategorised place should fix every breakdown that mentions it.

alter table public.plan_items
  add column activity_cost_php_cents integer not null default 0
    check (activity_cost_php_cents >= 0);

comment on column public.plan_items.activity_cost_php_cents is
  'What the attached activity adds for the whole party, computed at write time '
  'from activities.min_budget_php_cents, cost_kind and budget_is_per_person. '
  'Zero when no activity is attached and when the activity is venue spend, '
  'which the place price already carries. Separate from est_cost_php_cents so '
  'the places line stays the places line.';

-- ---------------------------------------------------------------------------
-- write_plan_stops — now costs the attached activity too.
-- ---------------------------------------------------------------------------
create or replace function public.write_plan_stops(
  p_plan_id     uuid,
  p_stops       jsonb,
  p_party       integer,
  p_origin_area text,
  p_origin_lat  double precision,
  p_origin_lng  double precision
) returns integer
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  stop      jsonb;
  seq_no    integer;
  place_row record;
  act_row   record;
  act_cents integer;
  item_id   uuid;
  item_ids  uuid[] := '{}';

  prev_area text;
  prev_lat  double precision;
  prev_lng  double precision;
  leg_dist  integer;
  leg       record;
begin
  prev_area := p_origin_area;
  prev_lat  := p_origin_lat;
  prev_lng  := p_origin_lng;

  seq_no := 0;
  for stop in
    select value from jsonb_array_elements(coalesce(p_stops, '[]'::jsonb))
  loop
    select p.id, p.lat, p.lng, p.barangay, p.price_min_php_cents
      into place_row
    from public.places p
    where p.id = (stop ->> 'place_id')::uuid;

    -- A stop naming a place that no longer exists — or one belonging to another
    -- user, which RLS makes indistinguishable from missing — is skipped rather
    -- than stored as a hole. Writing is not the moment to invent a row.
    continue when place_row.id is null;

    -- What the attached activity adds, recomputed from the activity row rather
    -- than taken from the payload (invariant 3). A venue activity adds nothing:
    -- that money is the place's price, which est_cost_php_cents already holds.
    act_cents := 0;
    if nullif(stop ->> 'activity_id', '') is not null then
      select a.min_budget_php_cents, a.cost_kind, a.budget_is_per_person
        into act_row
      from public.activities a
      where a.id = (stop ->> 'activity_id')::uuid;

      if act_row.cost_kind = 'materials' then
        act_cents := coalesce(act_row.min_budget_php_cents, 0)
                     * case when act_row.budget_is_per_person then p_party else 1 end;
      end if;
    end if;

    insert into public.plan_items (
      plan_id, seq, activity_id, place_id, start_time, duration_minutes,
      est_cost_php_cents, activity_cost_php_cents, note
    ) values (
      p_plan_id, seq_no,
      nullif(stop ->> 'activity_id', '')::uuid,
      place_row.id,
      nullif(stop ->> 'start_time', '')::timestamptz,
      nullif(stop ->> 'duration_minutes', '')::integer,
      -- Invariant 3: recomputed, never the payload's figure.
      coalesce(place_row.price_min_php_cents, 0) * p_party,
      act_cents,
      stop ->> 'note'
    )
    returning id into item_id;

    -- The leg INTO this stop, derived rather than read. The payload's `legs`
    -- array is ignored completely — fewer inputs to trust beats more inputs to
    -- validate.
    leg_dist := public.haversine_m(prev_lat, prev_lng, place_row.lat, place_row.lng);
    select * into leg
    from public.fare_for(prev_area, place_row.barangay, leg_dist, p_party);

    insert into public.plan_legs (
      plan_id, from_item_id, to_item_id, seq, mode, distance_m, fare_php_cents
    ) values (
      p_plan_id,
      case when seq_no = 0 then null else item_ids[seq_no] end,
      item_id,
      seq_no,
      leg.mode,
      leg_dist,
      -- Null when no fare was recorded. Null is a fact here, not a gap: it is
      -- what stops an unpriced leg being silently counted as free.
      case when leg.fare_known then leg.fare_php_cents else null end
    );

    item_ids  := item_ids || item_id;
    prev_area := place_row.barangay;
    prev_lat  := place_row.lat;
    prev_lng  := place_row.lng;
    seq_no    := seq_no + 1;
  end loop;

  return seq_no;
end;
$$;

comment on function public.write_plan_stops is
  'Writes plan_items and plan_legs for an ordered stop list, recomputing every '
  'distance, fare, activity budget and peso from the database (invariant 3). '
  'The single recompute path: save_plan and edit_plan both call it so a saved '
  'plan and an edited plan cannot disagree about a fare.';

-- ---------------------------------------------------------------------------
-- read_plan — the same totals shape both composers return.
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
        'activity_price_php_cents', i.activity_cost_php_cents,
        'distance_m', coalesce(public.haversine_m(
          (select lat from origin), (select lng from origin), p.lat, p.lng), 0),
        'start_time', i.start_time,
        'duration_minutes', i.duration_minutes,
        'note', i.note
      ) as stop,
      i.est_cost_php_cents,
      i.activity_cost_php_cents,
      -- Derived at read time on purpose: category belongs to the place, so
      -- recategorising one place should fix every breakdown that mentions it.
      public.cost_line_for_place(p.category) as cost_line
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
  ),
  money as (
    select
      coalesce((select sum(est_cost_php_cents) from stops), 0)      as places_cents,
      coalesce((select sum(fare_php_cents) from legs), 0)           as fares_cents,
      coalesce((select sum(activity_cost_php_cents) from stops), 0) as act_cents,
      coalesce((select sum(est_cost_php_cents) from stops
                where cost_line = 'food'), 0)                       as line_food,
      coalesce((select sum(est_cost_php_cents) from stops
                where cost_line = 'gifts'), 0)                      as line_gifts,
      coalesce((select sum(est_cost_php_cents) from stops
                where cost_line = 'activities'), 0)                 as line_activities
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
        'places_php_cents', (select places_cents from money),
        'fares_php_cents', (select fares_cents from money),
        'activities_php_cents', (select act_cents from money),
        'total_php_cents',
          (select places_cents + fares_cents + act_cents from money),
        'unpriced_legs', (select count(*) from legs where fare_php_cents is null),
        'is_complete', (select count(*) from legs where fare_php_cents is null) = 0,
        'lines', jsonb_build_object(
          'fares', (select fares_cents from money),
          'food', (select line_food from money),
          'materials', (select act_cents from money),
          'activities', (select line_activities from money),
          'gifts', (select line_gifts from money)
        )
      ),
      'candidate_activities', '[]'::jsonb
    )
  end;
$$;

comment on function public.read_plan(uuid) is
  'Returns a saved plan in the same shape both composers produce, including '
  'totals.lines. Place lines are derived from cost_line_for_place at read time; '
  'materials come from plan_items.activity_cost_php_cents, stored at write time '
  'so a later price edit cannot rewrite the cost of an outing already had.';
