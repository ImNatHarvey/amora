-- Cover the two Phase 0 foreign keys that had no index.
--
-- places.submitted_by_user_id is read by the places RLS policy on every select,
-- so it wants an index before user submissions exist (Phase 5), not after. It is
-- a partial index because the column is null for every curated row — which is
-- almost all of them — and there is no reason to index those nulls.
create index places_submitted_by_user_id_idx
  on public.places (submitted_by_user_id)
  where submitted_by_user_id is not null;

-- user_resources.resource_id is the join back to resource_catalog when showing
-- what a user owns (Phase 1).
create index user_resources_resource_id_idx
  on public.user_resources (resource_id);
