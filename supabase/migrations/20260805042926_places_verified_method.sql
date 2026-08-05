-- places.verified_method — how a row's facts were established.
--
-- The catalogue is mixed-provenance for the first time. docs/00-architecture.md
-- §10.4a admits three ways a person may establish a row: standing at the door,
-- phoning the place, or — for a fact that does not move, about a place with no
-- price to be wrong about — a resident's own first-hand knowledge.
--
-- All three are legitimate and they are not equally strong. A phoned price and a
-- seen price differ; a resident's "the plaza is free and open air" and a resident's
-- "that cafe is about ₱150" differ so much that only the first is allowed at all.
-- Nothing else in the schema records which of the three produced a row, which
-- makes the catalogue unauditable exactly where auditing matters.
--
-- Nullable, because the 15 test-* placeholders predate it and are being deleted
-- rather than backfilled. The value set is constrained; the semantic rule — that a
-- priced row can never be 'resident' — is enforced in csv_to_sql.mjs, where a
-- violation can name the file and line that caused it.
alter table public.places
  add column verified_method text
  constraint places_verified_method_allowed
    check (verified_method in ('visited', 'phoned', 'resident'));

comment on column public.places.verified_method is
  'How this row was established: visited (stood at the door), phoned (called the '
  'place), or resident (first-hand knowledge of a stable fact about a free public '
  'place). See docs/00-architecture.md §10.4a. A priced row may never be resident.';
