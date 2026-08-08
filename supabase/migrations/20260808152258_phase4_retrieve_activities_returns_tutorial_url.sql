-- Phase 4 — retrieve_activities returns tutorial_url
--
-- `activities.tutorial_url` has existed since the Phase 0 schema and nothing has
-- ever read it: retrieval did not select it, so no caller could render it. That
-- is why Phase 4's "a DIY activity plays its tutorial in-app" criterion was
-- deferred — the column was unreachable, not merely empty.
--
-- Adding a column to the return table is not a `create or replace`: Postgres
-- refuses to change an existing function's return type. Drop first, recreate,
-- then reissue the comment and the grants. All three need the full argument
-- list, because a bare name is ambiguous once overloads exist (and reissuing
-- them is mandatory regardless — a dropped function takes its grants with it,
-- and Postgres hands EXECUTE back to PUBLIC on the new one).
--
-- Every existing caller survives this by construction, which was checked rather
-- than assumed:
--   * `cost_generated_plan` selects `a.activity_id` only.
--   * `build_simple_plan` does `to_jsonb(a)`, so `candidate_activities` gains
--     the field — additive, and it reaches the same `Activity.fromMap` the
--     Ideas screen uses, so one model change serves both surfaces.
--   * `generate-plan`'s prompt builder emits `activity_id | title | category`
--     and nothing else, so the model's view is unchanged. Invariant 1 holds:
--     widening what retrieval returns is not widening what the model is told.

drop function if exists public.retrieve_activities(integer, uuid[]);

create function public.retrieve_activities(
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
  is_diy boolean,
  tutorial_url text
)
language sql
stable
set search_path = ''
as $$
  select
    a.id, a.slug, a.title, a.category,
    a.min_budget_php_cents, a.max_budget_php_cents, a.duration_minutes,
    a.weather_dependent, a.is_diy, a.tutorial_url
  from public.activities a
  where a.min_budget_php_cents <= p_budget_php_cents
    and a.required_resource_ids <@ coalesce(p_owned_resource_ids, '{}'::uuid[])
  order by a.min_budget_php_cents, a.slug;
$$;

comment on function public.retrieve_activities(integer, uuid[]) is
  'Activities within budget whose required resources the user already owns. '
  'tutorial_url is null for every row until one is curated — see D5: a link is '
  'collected and checked, never generated.';

revoke execute on function
  public.retrieve_activities(integer, uuid[])
from public, anon;

grant execute on function
  public.retrieve_activities(integer, uuid[])
to authenticated;
