-- Marks when a user finished the "what do you already have?" step.
--
-- Needed because owning nothing is a legitimate answer. Without this column,
-- an empty user_resources set is ambiguous — it could mean the user picked
-- nothing, or that they never reached the picker — and onboarding would send
-- them back to it forever.
--
-- Nullable on purpose: null means not yet onboarded. Existing RLS already
-- covers it, since the profiles policies are row-scoped rather than
-- column-scoped.
alter table public.profiles
  add column onboarded_at timestamptz;

comment on column public.profiles.onboarded_at is
  'Set when the resource picker is completed. Null means onboarding is unfinished.';
