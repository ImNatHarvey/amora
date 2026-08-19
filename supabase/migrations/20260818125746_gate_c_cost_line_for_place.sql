-- Which breakdown line a place's cost belongs on.
--
-- A function rather than a CASE inside each composer, because **both**
-- build_simple_plan and cost_generated_plan have to agree. This repository has
-- shipped the same bug four times from one rule having two homes — party size,
-- _pesos, _apply, and the two copies of the Edge Function helpers — and a
-- breakdown that disagreed with itself between the crude builder and the model
-- would be the fifth.
--
-- The default is 'activities' and it is deliberate, not a fallthrough: a court
-- fee, a park entry or a paid viewpoint is money spent in order to do
-- something. No category is silently dropped — every peso lands on exactly one
-- line, which is what makes the lines sum to the total.

create or replace function public.cost_line_for_place(p_category text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case lower(coalesce(p_category, ''))
    when 'cafe'       then 'food'
    when 'food'       then 'food'
    when 'restaurant' then 'food'
    when 'market'     then 'food'
    when 'bakery'     then 'food'
    when 'florist'    then 'gifts'
    when 'vendor'     then 'gifts'
    when 'gift'       then 'gifts'
    else 'activities'
  end;
$$;

comment on function public.cost_line_for_place(text) is
  'Maps places.category to a price-breakdown line: food, gifts or activities. '
  'Shared by build_simple_plan and cost_generated_plan so the two composers '
  'cannot disagree. The default is activities — paying to be somewhere is '
  'paying to do something — and nothing is dropped, so the lines sum to the '
  'total.';

revoke execute on function public.cost_line_for_place(text) from public, anon;
grant execute on function public.cost_line_for_place(text) to authenticated;
