-- places.verified_method gains 'generated' — a row nobody established at all.
--
-- Nat asked for a catalogue he can hold and use on a phone before the desk run
-- in supabase/seed/DESK-CHECKLIST.md has happened. Fifteen plausible Bocaue rows
-- were generated for that, and the honest question is where the database records
-- that they are generated.
--
-- Not verification_tier. That column answers *did a user submit this* — its two
-- values are 'curated' and 'user_submitted', and `= 'curated'` is filtered at
-- eight sites including places_read RLS, retrieve_candidates, build_simple_plan
-- and places_version(). Adding a third value there would widen the guard that
-- keeps one bad user row out of every other user's results, which is invariant
-- 5's entire mechanism, in exchange for a demo convenience. These rows were
-- entered by the owner, so 'curated' is the truthful answer to the question that
-- column actually asks.
--
-- verified_method asks *how were these facts established*, which is the question
-- with the uncomfortable answer, and §10.4a created it precisely so a
-- mixed-provenance catalogue stays auditable. Nothing filters on it, so this
-- widening changes no retrieval, no RLS and no costing path.
--
-- 'generated' is not a fourth way to establish a fact. It is the absence of one,
-- recorded where a reader will find it. verified_on stays null, because there is
-- no date on which anybody checked. Rows carry a demo- slug prefix, and
-- csv_to_sql.mjs enforces that pairing in both directions so the wipe in
-- supabase/seed/wipe-demo.sql stays exact.
alter table public.places
  drop constraint places_verified_method_allowed;

alter table public.places
  add constraint places_verified_method_allowed
    check (verified_method in ('visited', 'phoned', 'resident', 'generated'));

comment on column public.places.verified_method is
  'How this row was established: visited (stood at the door), phoned (called the '
  'place), resident (first-hand knowledge of a stable fact about a free public '
  'place), or generated (demo data, established by nobody — see '
  'supabase/seed/DEMO-DATA.md). See docs/00-architecture.md §10.4a. A priced row '
  'may never be resident.';
