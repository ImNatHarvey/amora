-- The applied-migration ledger, readable by a local script.
--
-- Three separate incidents have now come from the same cause: the repository
-- and the project disagreeing about what has been applied, with nothing able to
-- notice.
--
--   1. The deployed `generate-plan` bundle was two versions behind disk for a
--      fortnight, which is what made Phase 3's acceptance fail 11 of 20.
--   2. Two Phase 6 migrations were committed under filenames that did not match
--      the version `apply_migration` stamped, so a later `db push` would have
--      replayed them.
--   3. Two Gate C migrations were applied and never committed at all — they sat
--      orphaned between two commits until the next session happened to look.
--
-- Each was found by hand, late, and after being written up as a routine that
-- then did not hold. A routine that needs remembering is not a control. This
-- function is what lets `supabase/check-drift.mjs` be run instead.
--
-- SECURITY DEFINER because `supabase_migrations` is not reachable by anon or
-- authenticated, and `search_path` is pinned like every other definer function
-- here.
--
-- Granted to anon deliberately. It returns migration versions and an md5 of
-- their text — and **this repository is public**, so every one of those
-- statements is already readable on GitHub by anyone who wants them. It exposes
-- no row of user data, no table contents, and no write path. The alternative
-- was a service-role key on a developer machine, which is a far worse trade for
-- a check that has to be cheap enough to run every session.
create or replace function public.migration_ledger()
returns table (version text, statements_md5 text)
language sql
stable
security definer
set search_path = ''
as $$
  select m.version, md5(array_to_string(m.statements, E'\n'))
  from supabase_migrations.schema_migrations m
  order by m.version;
$$;

comment on function public.migration_ledger() is
  'Applied migration versions and an md5 of each one''s text, so a local script '
  'can prove the repository and the project agree. Read-only, no user data, and '
  'the statements it hashes are public in the repo already. Used by '
  'supabase/check-drift.mjs.';

revoke execute on function public.migration_ledger() from public;
grant execute on function public.migration_ledger() to anon, authenticated;
