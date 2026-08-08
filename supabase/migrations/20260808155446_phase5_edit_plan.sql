-- Phase 5 — editing a plan, on one recompute path.
--
-- An edit is a new ordered stop list. save_plan already turns exactly that into
-- costed items and legs, so the work here is not to write a second composer —
-- it is to make sure there is only ever one.
--
-- write_plan_stops is save_plan's loop, lifted out unchanged. Both save_plan
-- and edit_plan call it. That is deliberate and it is the whole point of the
-- migration: two copies of this loop would mean a saved plan and an edited plan
-- could disagree about a fare, and this repo has already shipped that exact bug
-- class twice — party size living in two files, and _pesos duplicated
-- byte-for-byte across two screens. Both were found late, and both were only
-- possible because one rule had two homes.

-- ---------------------------------------------------------------------------
-- write_plan_stops — the one place items and legs are written
--
-- security invoker, so the caller's RLS applies. plan_items and plan_legs both
-- check ownership through their parent plan, so this cannot write into someone
-- else's plan however it is called. Granted to authenticated because save_plan
-- and edit_plan are themselves invoker-rights: revoking it here would break
-- them for every real user while leaving it callable by nobody.
-- ---------------------------------------------------------------------------
create function public.write_plan_stops(
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

    insert into public.plan_items (
      plan_id, seq, activity_id, place_id, start_time, duration_minutes,
      est_cost_php_cents, note
    ) values (
      p_plan_id, seq_no,
      nullif(stop ->> 'activity_id', '')::uuid,
      place_row.id,
      nullif(stop ->> 'start_time', '')::timestamptz,
      nullif(stop ->> 'duration_minutes', '')::integer,
      -- Invariant 3: recomputed, never the payload's figure.
      coalesce(place_row.price_min_php_cents, 0) * p_party,
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
  'distance, fare and peso from the database (invariant 3). The single '
  'recompute path: save_plan and edit_plan both call it so a saved plan and an '
  'edited plan cannot disagree about a fare.';

-- ---------------------------------------------------------------------------
-- save_plan — unchanged behaviour, now delegating the loop.
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
  origin_area  text;
  origin_lat   double precision;
  origin_lng   double precision;
  city         text;
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

  perform public.write_plan_stops(
    new_plan_id, p_payload -> 'stops', party,
    origin_area, origin_lat, origin_lng);

  return new_plan_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- edit_plan — reorder, remove, retime, add
--
-- Takes the whole new ordered stop list rather than a delta. Order is the
-- user's to decide, so it is the one thing the client is authoritative about;
-- every peso stays server-derived. A delta API would need four code paths that
-- must each recompute legs correctly, which is four chances to get it wrong
-- against one.
--
-- Returns the recomputed plan in read_plan's shape, so always-live editing
-- costs one round trip per change instead of a write followed by a read — and
-- so the client can never render a total it computed itself.
-- ---------------------------------------------------------------------------
create function public.edit_plan(
  p_plan_id         uuid,
  p_edit_type       text,
  p_stops           jsonb,
  p_target_place_id uuid default null,
  p_target_item_id  uuid default null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  plan_row   record;
  origin_lat double precision;
  origin_lng double precision;
  city       text;
begin
  if auth.uid() is null then
    raise exception 'edit_plan requires an authenticated user';
  end if;

  if p_edit_type not in ('add', 'remove', 'reorder', 'retime') then
    raise exception 'edit_plan: % is not an edit type', p_edit_type;
  end if;

  -- RLS restricts this to the caller's own plans, so "not found" and "not
  -- yours" arrive identically — which is what read_plan already relies on.
  select * into plan_row from public.plans where id = p_plan_id;
  if plan_row.id is null then
    raise exception 'edit_plan: no such plan';
  end if;

  city := coalesce((select pr.city from public.profiles pr
                    where pr.id = auth.uid()), 'Bocaue');

  select o.lat, o.lng into origin_lat, origin_lng
  from public.origin_areas(city) o
  where o.area = plan_row.origin_area;

  if origin_lat is null then
    raise exception
      'edit_plan: this plan starts from %, which no longer has curated places',
      coalesce(plan_row.origin_area, '(none)');
  end if;

  -- Legs first: they reference items, and being explicit beats relying on the
  -- cascade to fire in the order we happen to need.
  delete from public.plan_legs  where plan_id = p_plan_id;
  delete from public.plan_items where plan_id = p_plan_id;

  perform public.write_plan_stops(
    p_plan_id, p_stops, plan_row.party_size,
    plan_row.origin_area, origin_lat, origin_lng);

  -- Invariant 7: one row per edit, always. Written after the rewrite so a
  -- failed edit logs nothing rather than logging a lie.
  insert into public.plan_edits (
    plan_id, user_id, edit_type, target_item_id, target_place_id
  ) values (
    p_plan_id, auth.uid(), p_edit_type, p_target_item_id, p_target_place_id
  );

  return public.read_plan(p_plan_id);
end;
$$;

comment on function public.edit_plan is
  'Reorder, remove, retime or add a stop. Rewrites items and legs from the new '
  'ordered list through write_plan_stops, logs one plan_edits row, and returns '
  'the recomputed plan in read_plan''s shape.';

revoke execute on function
  public.write_plan_stops(uuid, jsonb, integer, text, double precision, double precision),
  public.edit_plan(uuid, text, jsonb, uuid, uuid)
from public, anon;

grant execute on function
  public.write_plan_stops(uuid, jsonb, integer, text, double precision, double precision),
  public.edit_plan(uuid, text, jsonb, uuid, uuid)
to authenticated;
