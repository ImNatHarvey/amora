-- Gate A — preferences on the profile.
--
-- Three columns, all nullable-or-empty, because a profile created by the
-- on_auth_user_created trigger has none of them and must stay valid. A user who
-- never opens the preferences screen is a supported state, not a broken one.
--
-- RLS is deliberately untouched: profiles_select_own and profiles_update_own
-- already scope every row to auth.uid(), and adding columns to a table does not
-- widen a policy that filters on the primary key.

alter table public.profiles
  -- Stored as text rather than an enum so widening the persona later is a
  -- constraint change, not a type migration with a rewrite. 00-architecture.md
  -- §11 lists this as one of the decisions that must not be made couple-shaped.
  --
  -- The check permits all five values while the UI offers only 'partner'
  -- (D1, and CLAUDE.md's not-building list). Storage is ready; the product
  -- decision is not. Enabling the rest is a change to one Dart list.
  add column companion_type text
    check (companion_type is null
           or companion_type in ('partner', 'friends', 'family', 'solo', 'group')),

  -- Activity category slugs, matching public.activities.category. Not a
  -- separate vocabulary: an interest that maps to no category could never
  -- change a single result, which is exactly the dead-weight problem the
  -- resource catalogue just had.
  --
  -- NOT NULL with a default so every read is an array and no caller has to
  -- decide what null interests mean.
  add column interests text[] not null default '{}',

  -- The user's usual spend for a whole outing, in centavos — a default for the
  -- intake budget chip, never a cap on what they may request (§9: the budget is
  -- the whole date, not per person).
  add column usual_budget_php_cents integer
    check (usual_budget_php_cents is null or usual_budget_php_cents >= 0);

comment on column public.profiles.companion_type is
  'Who the user usually plans with. Storage permits five values; the UI offers '
  'only partner while D1 holds. See 00-architecture.md §11.';

comment on column public.profiles.interests is
  'Activity category slugs to rank by, never to filter by. Empty means no '
  'preference, which must return the same set as every category selected.';

comment on column public.profiles.usual_budget_php_cents is
  'Default for the intake budget chip, in centavos, for the whole party. Never '
  'a cap.';
