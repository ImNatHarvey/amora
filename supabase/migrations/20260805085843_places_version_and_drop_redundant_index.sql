-- places_version() — what makes plan_cache able to forget.
--
-- The bug this closes: the Edge Function hardcoded `placesVersion = 1`, so the
-- column that exists specifically to evict stale plans never changed. Correct a
-- price in the seed CSV, re-import, and every cached plan built on the old
-- number keeps being served — forever, silently, and with exactly the confident
-- wrong total §10.2 says costs the evening.
--
-- No new column and no new table, because the signal already exists:
-- csv_to_sql.mjs writes `verified_at = now()` on every upsert, so the newest
-- verified_at moves whenever any row is imported or corrected. Counting rows
-- alongside it catches the one case a timestamp misses — a place deleted, which
-- changes what retrieval returns without touching anyone's verified_at.
--
-- Deliberately coarse. This is a cache key ingredient, not an audit log: it has
-- to change when the catalogue changes and be stable when it does not. Both
-- hold. It over-invalidates when an unrelated place is corrected, which costs
-- one extra generation and is the safe direction to be wrong in.
create or replace function public.places_version()
returns bigint
language sql
stable
parallel safe
set search_path = ''
as $$
  select coalesce(
    extract(epoch from max(p.verified_at))::bigint + count(*),
    0
  )
  from public.places p
  where p.verification_tier = 'curated';
$$;

comment on function public.places_version() is
  'A number that changes whenever the curated catalogue does. Folded into the '
  'plan_cache key so a corrected price evicts the plans built on the old one. '
  'Coarse on purpose: over-invalidating costs one generation, under-'
  'invalidating serves a wrong total forever.';

-- The Edge Function reads this with the service role, but retrieval-adjacent
-- functions are granted to authenticated for symmetry with fare_for and
-- haversine_m, and this leaks nothing: it is an aggregate over rows the anon
-- role can already read.
revoke execute on function public.places_version() from public, anon;
grant execute on function public.places_version() to authenticated;

-- ---------------------------------------------------------------------------
-- Drop a redundant index.
--
-- plan_cache.constraint_hash is declared UNIQUE, and Postgres backs a unique
-- constraint with its own index. plan_cache_constraint_hash_idx was therefore a
-- second index on the same column doing the same job — added by hand in the
-- Phase 3 migration without noticing the constraint already covered it. It
-- costs a write on every cache insert and buys nothing.
-- ---------------------------------------------------------------------------
drop index if exists public.plan_cache_constraint_hash_idx;
