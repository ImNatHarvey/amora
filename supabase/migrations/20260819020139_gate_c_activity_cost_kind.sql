-- Gate C, part 1 — what kind of money an activity's budget is.
--
-- `activities.min_budget_php_cents` has always meant two different things at
-- once, and nothing in the schema said which. For `bake-something` it is
-- ingredients bought at a shop before the date; for `cafe-hopping` it is the
-- money spent at the cafe — which is already `places.price_min_php_cents` at
-- the stop the model paired it with. Summing the column would therefore double
-- the second kind, and not summing it (today's behaviour) silently drops the
-- first.
--
-- Zeroing the venue rows was considered and rejected: `retrieve_activities`
-- filters on that column, so a zero-budget `cafe-hopping` would surface on a
-- free-date search, and cafe hopping is not free. What the budget *costs* and
-- whether a plan has *already counted it* are two different facts and need two
-- columns.
--
-- `budget_is_per_person` is the same shape `transit_fares.is_per_person`
-- already has, for the same reason: a jeepney charges each passenger, a
-- tricycle special trip charges once for the vehicle — and a couple baking
-- together buys one set of ingredients, not two (docs/00-architecture.md §9).
alter table public.activities
  add column cost_kind text not null default 'materials'
    check (cost_kind in ('materials', 'venue')),
  add column budget_is_per_person boolean not null default true;

comment on column public.activities.cost_kind is
  'Whether this activity''s budget is additive to a plan total. `materials` is '
  'bought elsewhere and adds; `venue` is spent at the paired place and is '
  'already counted as that place''s price. Defaults to `materials` on purpose: '
  'a wrong `venue` drops money silently, while a wrong `materials` over-states '
  'and the over-budget colour and icon make that visible.';

comment on column public.activities.budget_is_per_person is
  'False when one purchase serves the whole party — one batch of ingredients, '
  'one scrapbook, one pack of film. True when the spend scales per head. Mirrors '
  'transit_fares.is_per_person; see docs/00-architecture.md §9.';

-- Backfill. Only the two rows whose money is spent at the paired place, and the
-- rows where one purchase serves both people.
update public.activities
set cost_kind = 'venue'
where slug in ('cafe-hopping', 'street-food-crawl');

update public.activities
set budget_is_per_person = false
where slug in (
  'bake-something',        -- one batch
  'cook-a-meal-together',  -- one meal
  'grill-together',        -- one grill
  'scrapbook-making',      -- one scrapbook
  'wrap-a-surprise',       -- one wrapped gift
  'diy-paper-flowers',     -- one bunch
  'instant-photo-hunt'     -- one pack of film
);
-- `pack-a-cooler` stays per person: drinks and snacks scale with heads.
