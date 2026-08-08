-- Phase 5 review — save_plan and edit_plan disagreed about which city a plan is in.
--
-- save_plan resolved it as:
--
--   select p.city from profiles pr join places p on p.city = pr.city
--   where pr.id = auth.uid() limit 1        -- else 'Bocaue'
--
-- which returns the profile's city only if some place already exists there, and
-- silently falls back to Bocaue otherwise. edit_plan (Phase 5) read pr.city
-- directly. For a user whose city holds no curated places the two disagree, and
-- the failure is not a wrong number — it is that save_plan writes an
-- origin_area drawn from Bocaue's origin_areas while edit_plan then looks that
-- area up in a different city's, finds nothing, and raises "this plan starts
-- from X, which no longer has curated places" on every edit. The plan becomes
-- permanently uneditable.
--
-- Unreachable today, because profile setup fixes city to Bocaue (D1). That is
-- precisely why it is worth fixing now: the bug arrives on the day coverage
-- expands, which is the day nobody will be looking at save_plan.
--
-- plan_city() is the single expression. The fallback stays — a profile with no
-- city must still be able to plan — but it no longer depends on whether the
-- catalogue happens to have reached that city yet, which was never what the
-- question meant.

create function public.plan_city()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (select pr.city from public.profiles pr where pr.id = (select auth.uid())),
    'Bocaue');
$$;

comment on function public.plan_city is
  'The city the signed-in user plans in. One expression, so save_plan and '
  'edit_plan cannot disagree about which origin_areas a plan belongs to.';

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
  city        := public.plan_city();

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

create or replace function public.edit_plan(
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
begin
  if auth.uid() is null then
    raise exception 'edit_plan requires an authenticated user';
  end if;

  if p_edit_type not in ('add', 'remove', 'reorder', 'retime') then
    raise exception 'edit_plan: % is not an edit type', p_edit_type;
  end if;

  select * into plan_row from public.plans where id = p_plan_id;
  if plan_row.id is null then
    raise exception 'edit_plan: no such plan';
  end if;

  select o.lat, o.lng into origin_lat, origin_lng
  from public.origin_areas(public.plan_city()) o
  where o.area = plan_row.origin_area;

  if origin_lat is null then
    raise exception
      'edit_plan: this plan starts from %, which no longer has curated places',
      coalesce(plan_row.origin_area, '(none)');
  end if;

  delete from public.plan_legs  where plan_id = p_plan_id;
  delete from public.plan_items where plan_id = p_plan_id;

  perform public.write_plan_stops(
    p_plan_id, p_stops, plan_row.party_size,
    plan_row.origin_area, origin_lat, origin_lng);

  insert into public.plan_edits (
    plan_id, user_id, edit_type, target_item_id, target_place_id
  ) values (
    p_plan_id, auth.uid(), p_edit_type, p_target_item_id, p_target_place_id
  );

  return public.read_plan(p_plan_id);
end;
$$;

revoke execute on function public.plan_city() from public, anon;
grant execute on function public.plan_city() to authenticated;
