-- Phase 6 — the one column §5 reserved for this phase.
--
-- A tiny migration on purpose. plan_legs was created in Phase 3 with every
-- other column §5 lists; actual_fare_php_cents was held back because nothing
-- could write it until there was a completion flow. It lands here, separately
-- from the function that writes it, so "what may be recorded" and "how it is
-- written" stay two reviewable changes rather than one.
--
-- Why this column exists at all, from §5: fares drift faster than menu prices
-- and no API tracks them (D5). A jeepney raising its fare by ₱2 is invisible to
-- every source Amora could ever buy. This is the ONLY correction signal transit
-- will ever get — which is why it is worth a column and a UI field rather than
-- being folded into the plan-level spend figure.
--
-- It is a PARTY total, matching fare_php_cents beside it. fare_for already
-- resolves is_per_person, so both columns mean "what this leg cost the couple"
-- and can be compared directly. Storing one per-person and one per-party would
-- reintroduce exactly the §9 confusion that made totals wrong by 2×.
--
-- Nullable, and null is the ordinary case: it means nobody corrected this leg.
-- Distinct from zero, which means they walked or the ride was free. Collapsing
-- the two would make "not reported" indistinguishable from "reported as free",
-- and a null-as-zero would drag every future fare average toward nothing.
--
-- No new policy or grant is needed: plan_legs has had plan_legs_update_own and
-- an UPDATE grant since Phase 3, both scoped through the parent plan's owner,
-- so complete_plan can write this as security invoker without widening anything.

alter table public.plan_legs
  add column actual_fare_php_cents integer
    check (actual_fare_php_cents >= 0);

comment on column public.plan_legs.actual_fare_php_cents is
  'What the couple really paid for this leg, in centavos — a PARTY total, like '
  'fare_php_cents beside it. Null means nobody corrected this leg, which is '
  'different from 0 meaning the leg was free. The only correction signal '
  'transit fares will ever get (§5, D5).';
