-- retrieve_activities gains p_interests — ordering only, never filtering.
--
-- The rule, and it is the whole design: a user who ticks nothing must get the
-- same activities as a user who ticks everything. Interests move rows up the
-- list; they never remove one. A picker that could hide the catalogue would let
-- someone quietly delete their own options while believing they expressed a
-- taste.
--
-- Adding a parameter makes an OVERLOAD rather than replacing the function, so
-- the two-argument signature is dropped first (HANDOFF gotcha). Existing callers
-- — build_simple_plan, cost_generated_plan and the generate-plan Edge Function —
-- all pass two arguments and resolve to this one through the default, so none
-- of them change.
--
-- The drop takes the grants with it, so the revoke/grant pair is reissued with
-- the full argument list.

drop function if exists public.retrieve_activities(integer, uuid[]);

create function public.retrieve_activities(
  p_budget_php_cents integer,
  p_owned_resource_ids uuid[] default '{}',
  p_interests text[] default '{}'
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
  order by
    -- Interested categories first. With no interests every row scores 1, which
    -- is the pre-existing ordering exactly — so the empty case is not a special
    -- case, it is the same query.
    case
      when a.category = any(coalesce(p_interests, '{}'::text[])) then 0
      else 1
    end,
    a.min_budget_php_cents,
    a.slug;
$$;

comment on function public.retrieve_activities(integer, uuid[], text[]) is
  'Activities within budget whose required resources the user already owns, '
  'ordered with the user''s interested categories first. p_interests ranks and '
  'never filters: an empty array must return the same rows as every category. '
  'tutorial_url is null for every row until one is curated — see D5.';

revoke execute on function
  public.retrieve_activities(integer, uuid[], text[])
from public, anon;

grant execute on function
  public.retrieve_activities(integer, uuid[], text[])
to authenticated;
