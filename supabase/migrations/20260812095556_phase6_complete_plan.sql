-- Phase 6 — how a completion is written.
--
-- One function, one round trip, one transaction. A completion writes four
-- things: plans.status, a memories row, one place_reports row per stop, and
-- plan_legs.actual_fare_php_cents. Splitting that across calls would let a
-- phone on mobile data leave a plan marked completed with no reports behind it,
-- or reports with no memory — and the reports are the only part nobody would
-- notice was missing until Phase 6b came looking for a corpus.
--
-- security invoker, so the caller's RLS applies throughout. Every table touched
-- already has an owner-scoped policy (plans and plan_legs since Phase 3,
-- memories and place_reports in this phase's first migration), so this function
-- cannot reach into another user's plan however it is called. It adds no
-- privilege; it only makes four writes atomic.
--
-- WHAT THIS FUNCTION DOES NOT DO: read a report, take a median, quarantine
-- anything, or compare a figure to the seeded price. All of that is Phase 6b,
-- gated on report volume rather than on code (§10.5). This one records.

-- ---------------------------------------------------------------------------
-- The wire contract, stated once because it hides an off-by-one
--
-- p_stop_spends: [{"seq": 1, "spent_php_cents": 24000}, ...]
-- p_leg_fares:   [{"seq": 1, "fare_php_cents": 9000}, ...]
--
-- seq is ONE-BASED, matching what read_plan emits (`i.seq + 1`, `l.seq + 1`)
-- and therefore matching what the app is holding when it builds the sheet.
-- plan_items.seq and plan_legs.seq are ZERO-based in the table. This function
-- does the subtraction in one place. The alternative — a positional array
-- aligned to the stop order — needs no arithmetic but fails silently when the
-- client's list and the server's have drifted, and a completion is the last
-- moment you want a figure attributed to the wrong café.
--
-- An unknown seq RAISES rather than being ignored. The user typed that number;
-- dropping it quietly would produce a completion that looks fine and is missing
-- a report, which is precisely the class of bug this repo has shipped twice by
-- letting one rule live in two places.
--
-- A null or absent figure is legitimate and is stored as null: "we were there,
-- it was open, we did not record what it cost". That row still carries
-- still_open = true, which is real evidence for 6b's closure rule even though
-- it contributes nothing to a median.
-- ---------------------------------------------------------------------------

create function public.complete_plan(
  p_plan_id     uuid,
  p_stop_spends jsonb   default '[]'::jsonb,
  p_leg_fares   jsonb   default '[]'::jsonb,
  p_rating      integer default null,
  p_caption     text    default null,
  p_photo_path  text    default null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  plan_row    record;
  item        record;
  stop_count  integer;
  leg_count   integer;
  bad_seq     text;
  spent       integer;
  stop_total  integer := null;
  fare_total  integer;
  new_memory  record;
begin
  if auth.uid() is null then
    raise exception 'complete_plan requires an authenticated user';
  end if;

  select * into plan_row from public.plans where id = p_plan_id;
  if plan_row.id is null then
    -- Missing and not-yours are the same answer, as everywhere else: RLS makes
    -- them indistinguishable and a client has no business telling them apart.
    raise exception 'complete_plan: no such plan';
  end if;

  -- Refused rather than made idempotent. memories.plan_id is unique, so a
  -- second attempt would fail anyway — but on a constraint name, which is not
  -- something to show a user. More importantly a silent second completion would
  -- double every place_report behind this plan, and 6b takes a median over
  -- those: one user's double tap would move a price further than the anti-gaming
  -- rules in §10.5 ever intended to allow.
  if plan_row.status = 'completed' then
    raise exception 'complete_plan: this plan is already completed';
  end if;

  if p_rating is not null and p_rating not between 1 and 5 then
    raise exception 'complete_plan: rating must be 1 to 5, got %', p_rating;
  end if;

  select count(*) into stop_count from public.plan_items where plan_id = p_plan_id;
  select count(*) into leg_count  from public.plan_legs  where plan_id = p_plan_id;

  -- A missing seq key is as wrong as an out-of-range one, and has to be tested
  -- for separately: `(e ->> 'seq')::integer not between ...` is NULL when the
  -- key is absent, and NULL is not true, so an entry with no seq would sail
  -- through a range check alone and then match no stop in the loop below. The
  -- user's figure would vanish silently, which is the failure mode this whole
  -- validation exists to prevent.
  select coalesce(e ->> 'seq', '(missing)') into bad_seq
  from jsonb_array_elements(coalesce(p_stop_spends, '[]'::jsonb)) e
  where (e ->> 'seq') is null
     or (e ->> 'seq')::integer not between 1 and stop_count
  limit 1;
  if bad_seq is not null then
    raise exception
      'complete_plan: stop % is not in this plan, which has % stops', bad_seq, stop_count;
  end if;

  select coalesce(e ->> 'seq', '(missing)') into bad_seq
  from jsonb_array_elements(coalesce(p_leg_fares, '[]'::jsonb)) e
  where (e ->> 'seq') is null
     or (e ->> 'seq')::integer not between 1 and leg_count
  limit 1;
  if bad_seq is not null then
    raise exception
      'complete_plan: leg % is not in this plan, which has % legs', bad_seq, leg_count;
  end if;

  -- -------------------------------------------------------------------------
  -- What they really paid to move. A party total, like fare_php_cents beside
  -- it, because fare_for has already resolved is_per_person.
  -- -------------------------------------------------------------------------
  update public.plan_legs l
  set actual_fare_php_cents = nullif(e ->> 'fare_php_cents', '')::integer
  from jsonb_array_elements(coalesce(p_leg_fares, '[]'::jsonb)) e
  where l.plan_id = p_plan_id
    and l.seq = (e ->> 'seq')::integer - 1;

  -- -------------------------------------------------------------------------
  -- One report per STOP (§8, §10.5). Not one per plan: a single spend figure
  -- cannot be attributed back to the café that was wrong, and 6b corrects per
  -- place.
  --
  -- THE DIVISION IS THE POINT OF THIS LOOP. The user enters what the couple
  -- handed over — the only figure a human actually knows — and
  -- places.price_min_php_cents, which 6b takes a median against, is what ONE
  -- person spends (§9). Store the party figure here and every median comes out
  -- at twice the truth while looking entirely plausible. party_size is read
  -- from the plan rather than assumed to be 2, so this survives D1 being lifted.
  --
  -- Integer division truncates, deliberately: ₱250 for two becomes ₱125 exactly,
  -- and an odd figure like ₱251 becomes ₱125 rather than ₱125.50. Money is
  -- integer centavos (CLAUDE.md) and a rounded centavo cannot matter to a rule
  -- whose threshold is 20%.
  -- -------------------------------------------------------------------------
  for item in
    select i.seq, i.place_id
    from public.plan_items i
    where i.plan_id = p_plan_id
    order by i.seq
  loop
    select nullif(e ->> 'spent_php_cents', '')::integer into spent
    from jsonb_array_elements(coalesce(p_stop_spends, '[]'::jsonb)) e
    where (e ->> 'seq')::integer = item.seq + 1
    limit 1;

    insert into public.place_reports (
      place_id, user_id, reported_cost_php_cents, still_open, plan_id
    ) values (
      item.place_id,
      auth.uid(),
      case when spent is null then null
           else spent / greatest(coalesce(plan_row.party_size, 1), 1) end,
      true,
      p_plan_id
    );

    if spent is not null then
      stop_total := coalesce(stop_total, 0) + spent;
    end if;
  end loop;

  -- -------------------------------------------------------------------------
  -- The plan-level figure, derived here and never sent by the device
  -- (invariant 3). The user is not asked for a total they have already given
  -- stop by stop.
  --
  -- A leg with no correction falls back to its computed fare, which is a
  -- database fact from transit_fares rather than an estimate of behaviour — and
  -- the user was shown it and left it, which is a confirmation. An unpriced leg
  -- stays out of the sum entirely, matching the "at least ₱X" convention the
  -- plan screen already uses for the same reason.
  --
  -- If NOT ONE stop figure was recorded, the total is NULL, not a fares-only
  -- number. "We do not know what this evening cost" is the honest answer;
  -- ₱90 of tricycle presented as the cost of a date is a wrong one.
  -- -------------------------------------------------------------------------
  select sum(coalesce(l.actual_fare_php_cents, l.fare_php_cents)) into fare_total
  from public.plan_legs l
  where l.plan_id = p_plan_id;

  update public.plans set status = 'completed' where id = p_plan_id;

  insert into public.memories (
    plan_id, user_id, photo_path, caption, actual_spend_php_cents, rating
  ) values (
    p_plan_id,
    auth.uid(),
    nullif(p_photo_path, ''),
    nullif(p_caption, ''),
    case when stop_total is null then null
         else stop_total + coalesce(fare_total, 0) end,
    p_rating::smallint
  )
  returning * into new_memory;

  return jsonb_build_object(
    'memory_id', new_memory.id,
    'plan_id', new_memory.plan_id,
    'photo_path', new_memory.photo_path,
    'caption', new_memory.caption,
    'actual_spend_php_cents', new_memory.actual_spend_php_cents,
    'rating', new_memory.rating,
    'created_at', new_memory.created_at,
    'reports_written', stop_count
  );
end;
$$;

comment on function public.complete_plan is
  'Marks a plan completed and writes, atomically: a memories row, one '
  'place_reports row per stop with the cost divided by party_size to per-person '
  '(§9), and plan_legs.actual_fare_php_cents. The plan total is derived here, '
  'never sent by the device (invariant 3). seq in both jsonb arguments is '
  'one-based, matching read_plan.';

-- ---------------------------------------------------------------------------
-- report_closure — the countermeasure to the self-concealing failure
--
-- §10.2: stale hours are the worst error we can ship, and the reason is not the
-- wasted fare. It is that the couple abandons the plan, so it is never
-- completed, so no report is written, so the correction loop never learns. The
-- failure with the highest cost produces the least signal.
--
-- So this deliberately requires nothing. No completion, no rating, no photo, no
-- plan at all — p_plan_id defaults to null so a closure can be reported while
-- browsing a place, and the check constraint on place_reports permits exactly
-- that for a report carrying no cost (§10.5's asymmetry). Every requirement
-- added here is a reason someone standing outside a locked door gives up
-- instead.
--
-- What it does check is attribution: a plan, if named, must be the caller's and
-- must actually contain that place. RLS already stops the first; the second is
-- this function's own, because a report tied to a plan the place was never in
-- is a claim 6b would age and trust.
--
-- §10.5's one-report-per-user-per-place-per-30-days cap is NOT enforced here.
-- It is a read-side rule and belongs with the code that reads — a cap applied at
-- write time would silently discard the second report a user files, which is
-- indistinguishable to them from the first not having worked. 6b filters; Phase
-- 6 records honestly.
-- ---------------------------------------------------------------------------
create function public.report_closure(
  p_place_id uuid,
  p_plan_id  uuid  default null,
  p_note     text  default null
) returns uuid
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'report_closure requires an authenticated user';
  end if;

  if not exists (select 1 from public.places where id = p_place_id) then
    raise exception 'report_closure: no such place';
  end if;

  if p_plan_id is not null then
    if not exists (
      select 1 from public.plans where id = p_plan_id
    ) then
      raise exception 'report_closure: no such plan';
    end if;

    if not exists (
      select 1 from public.plan_items
      where plan_id = p_plan_id and place_id = p_place_id
    ) then
      raise exception 'report_closure: that place is not a stop in that plan';
    end if;
  end if;

  insert into public.place_reports (
    place_id, user_id, reported_cost_php_cents, still_open, note, plan_id
  ) values (
    p_place_id, auth.uid(), null, false, nullif(p_note, ''), p_plan_id
  )
  returning id into new_id;

  return new_id;
end;
$$;

comment on function public.report_closure is
  'Records that a place was shut. Requires no completed plan and no plan at all '
  '(§10.5''s asymmetry): the couple who finds a locked door abandons the plan, '
  'so any requirement here blinds us to the failure that costs the most.';

-- ---------------------------------------------------------------------------
-- edit_plan — refuse a completed plan
--
-- Reproduced verbatim from 20260808163648 with one guard added. Its signature
-- and return type are unchanged, so create or replace is enough; a return-type
-- change would need a drop and a reissued revoke/grant pair with the full
-- argument list.
--
-- Why the guard: once a plan is completed, its place_reports say what each of
-- its stops cost. edit_plan deletes and rewrites plan_items on every edit, so
-- an edit afterwards would leave price reports attributed to a stop list that no
-- longer exists — and 6b reads those rows and trusts them. A removed stop's
-- report would go on nudging the median of a café the plan no longer visits.
-- ---------------------------------------------------------------------------
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

  if plan_row.status = 'completed' then
    raise exception
      'edit_plan: this plan is completed, and its reports describe the stops it has';
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

-- Following 20260731003449: nothing executable by anon or public by default.
revoke execute on function
  public.complete_plan(uuid, jsonb, jsonb, integer, text, text) from public, anon;
grant execute on function
  public.complete_plan(uuid, jsonb, jsonb, integer, text, text) to authenticated;

revoke execute on function
  public.report_closure(uuid, uuid, text) from public, anon;
grant execute on function
  public.report_closure(uuid, uuid, text) to authenticated;
