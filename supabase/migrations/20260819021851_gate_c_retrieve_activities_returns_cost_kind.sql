-- retrieve_activities returns cost_kind and budget_is_per_person.
--
-- The generate-plan prompt lists activities as `id | title | category` and says
-- nothing about money, so the model pairs a ₱200 activity with a stop having no
-- way to know it costs anything. Now that materials money reaches the total,
-- that is the difference between a plan that fits the budget and one flagged
-- over it — and the model cannot be asked to avoid a cost it was never shown.
--
-- Only materials money is additive, which is why cost_kind has to come with the
-- figure rather than the figure alone: quoting `cafe-hopping` as "from ₱200"
-- would make the model avoid it to protect a budget the place price already
-- accounts for. The Edge Function shows the cost for materials rows and stays
-- silent for venue rows.
--
-- This does not widen what the model may CLAIM (invariant 1) or let it do
-- arithmetic (invariant 3). It is retrieved data going in; every peso is still
-- computed by cost_generated_plan on the way out.
--
-- Adding a column to a return table is not a `create or replace` — Postgres
-- refuses to change a return type — so the three-argument signature is dropped
-- first and the revoke/grant pair reissued with the full argument list.

drop function if exists public.retrieve_activities(integer, uuid[], text[]);

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
  tutorial_url text,
  cost_kind text,
  budget_is_per_person boolean
)
language sql
stable
set search_path = ''
as $$
  select
    a.id, a.slug, a.title, a.category,
    a.min_budget_php_cents, a.max_budget_php_cents, a.duration_minutes,
    a.weather_dependent, a.is_diy, a.tutorial_url,
    a.cost_kind, a.budget_is_per_person
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
  'cost_kind and budget_is_per_person travel with the budget so a caller can '
  'tell additive materials money from venue spend the place price already '
  'carries. tutorial_url is null for every row until one is curated — see D5.';

revoke execute on function
  public.retrieve_activities(integer, uuid[], text[])
from public, anon;

grant execute on function
  public.retrieve_activities(integer, uuid[], text[])
to authenticated;
