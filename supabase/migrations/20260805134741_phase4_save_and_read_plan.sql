-- Phase 4 — saving a plan, and reading it back.
--
-- The tables have existed since Phase 3 with no writer, exactly as §5's phasing
-- note intended. This is the writer.
--
-- Why Postgres rather than three inserts from Dart:
--
-- 1. plan_legs references plan_items.id, so the write is ordered and belongs in
--    one transaction. Three round trips from a phone on mobile data is three
--    chances to leave a half-written plan behind.
-- 2. Invariant 3. save_plan RECOMPUTES each stop's cost from `places` and the
--    party size rather than storing the figure the client handed back. The
--    payload arrives from a device, and a device is not allowed to be the
--    authority on what something costs — even when it is only relaying what the
--    server computed a moment ago.
--
-- NOTE: this version still trusted the payload's FARES. That was caught by its
-- own invariant-3 test and fixed in 20260805134958, which also adds
-- plans.origin_area. Kept as applied; read the two together.

-- ---------------------------------------------------------------------------
-- save_plan
-- ---------------------------------------------------------------------------
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
  stop         jsonb;
  leg          jsonb;
  seq_no       integer;
  place_row    record;
  item_id      uuid;
  prev_item_id uuid := null;
  item_ids     uuid[] := '{}';
begin
  if auth.uid() is null then
    raise exception 'save_plan requires an authenticated user';
  end if;

  party       := greatest(coalesce((p_payload ->> 'party_size')::integer, 2), 1);
  budget      := coalesce((p_payload ->> 'budget_php_cents')::integer, 0);
  planned_for := coalesce(
    (p_payload ->> 'planned_for')::timestamptz, now());

  insert into public.plans (
    user_id, title, budget_php_cents, party_size, planned_for, status, origin,
    generated_by_model
  ) values (
    auth.uid(),
    coalesce(p_title, p_payload ->> 'title'),
    budget,
    party,
    planned_for,
    'draft',
    -- A model-composed plan says so; the Phase 2 builder leaves it null and the
    -- row reads 'generated' either way, because the user did not hand-build it.
    'generated',
    p_payload ->> 'generated_by_model'
  )
  returning id into new_plan_id;

  -- Stops, in the order the composer chose.
  seq_no := 0;
  for stop in select value from jsonb_array_elements(coalesce(p_payload -> 'stops', '[]'::jsonb))
  loop
    select p.id, p.price_min_php_cents
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
      new_plan_id,
      seq_no,
      nullif(stop ->> 'activity_id', '')::uuid,
      place_row.id,
      nullif(stop ->> 'start_time', '')::timestamptz,
      nullif(stop ->> 'duration_minutes', '')::integer,
      -- INVARIANT 3. Not stop->>'party_price_php_cents'. The client does not
      -- get to say what this costs, even when it is right.
      coalesce(place_row.price_min_php_cents, 0) * party,
      stop ->> 'note'
    )
    returning id into item_id;

    item_ids := item_ids || item_id;
    seq_no := seq_no + 1;
  end loop;

  -- Legs. The payload's leg N runs from (stop N-1, or the origin) to stop N,
  -- which is why the first leg's from_item_id is null.
  seq_no := 0;
  for leg in select value from jsonb_array_elements(coalesce(p_payload -> 'legs', '[]'::jsonb))
  loop
    exit when seq_no >= array_length(item_ids, 1);

    prev_item_id := case when seq_no = 0 then null else item_ids[seq_no] end;

    insert into public.plan_legs (
      plan_id, from_item_id, to_item_id, seq, mode, distance_m, fare_php_cents
    ) values (
      new_plan_id,
      prev_item_id,
      item_ids[seq_no + 1],
      seq_no,
      leg ->> 'mode',
      nullif(leg ->> 'distance_m', '')::integer,
      -- Null when no fare was recorded. Null is a fact here, not a gap: it is
      -- what stops an unpriced leg being silently counted as free.
      case when (leg ->> 'fare_known')::boolean
        then nullif(leg ->> 'fare_php_cents', '')::integer
        else null
      end
    );

    seq_no := seq_no + 1;
  end loop;

  return new_plan_id;
end;
$$;

comment on function public.save_plan(jsonb, text) is
  'Writes a costed plan to plans/plan_items/plan_legs and returns its id. '
  'Recomputes every peso from places rather than trusting the payload '
  '(invariant 3). RLS applies: security invoker, so a user can only write '
  'their own.';

-- ---------------------------------------------------------------------------
-- read_plan
--
-- Returns the SAME jsonb shape build_simple_plan and cost_generated_plan
-- return. That is the point: one Flutter renderer draws a fresh plan and a
-- reopened one, and they cannot disagree about a fare, because there is one
-- shape and one set of costing rules rather than two that have to be kept in
-- step by hand.
--
-- security invoker, so RLS decides what is visible. A plan belonging to someone
-- else returns null rather than an error — "not found" and "not yours" are the
-- same answer to a client that should not know the difference.
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
  stops as (
    select
      i.seq,
      jsonb_build_object(
        'seq', i.seq + 1,
        'place_id', p.id,
        'slug', p.slug,
        'activity_id', i.activity_id,
        'name', p.name,
        'category', p.category,
        'barangay', p.barangay,
        'lat', p.lat,
        'lng', p.lng,
        'opening_hours', p.opening_hours,
        'price_min_php_cents', p.price_min_php_cents,
        'price_max_php_cents', p.price_max_php_cents,
        'party_price_php_cents', i.est_cost_php_cents,
        'distance_m', 0,
        'start_time', i.start_time,
        'duration_minutes', i.duration_minutes,
        'note', i.note
      ) as stop,
      i.est_cost_php_cents
    from public.plan_items i
    join plan on plan.id = i.plan_id
    join public.places p on p.id = i.place_id
    order by i.seq
  ),
  legs as (
    select
      l.seq,
      jsonb_build_object(
        'seq', l.seq + 1,
        'from_name', coalesce(fp.name, (select 'origin')),
        'to_name', tp.name,
        'mode', l.mode,
        'distance_m', coalesce(l.distance_m, 0),
        'fare_php_cents', l.fare_php_cents,
        -- Reconstructed from whether a fare was stored, which is exactly what
        -- the null meant when it was written.
        'fare_known', l.fare_php_cents is not null
      ) as leg,
      l.fare_php_cents
    from public.plan_legs l
    join plan on plan.id = l.plan_id
    left join public.plan_items fi on fi.id = l.from_item_id
    left join public.places fp on fp.id = fi.place_id
    left join public.plan_items ti on ti.id = l.to_item_id
    left join public.places tp on tp.id = ti.place_id
    order by l.seq
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
        'area', coalesce((select barangay from public.places p
                          join public.plan_items i on i.place_id = p.id
                          join plan on plan.id = i.plan_id
                          order by i.seq limit 1), ''),
        'lat', null, 'lng', null),
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

comment on function public.read_plan(uuid) is
  'A saved plan in the same jsonb shape the two composers return, so one '
  'renderer draws both. security invoker: RLS decides visibility, and someone '
  'else''s plan reads as null rather than an error.';

revoke execute on function public.save_plan(jsonb, text) from public, anon;
revoke execute on function public.read_plan(uuid) from public, anon;
grant execute on function public.save_plan(jsonb, text) to authenticated;
grant execute on function public.read_plan(uuid) to authenticated;
