-- migration_ledger returns the statements themselves, not only a digest.
--
-- The drift check has to compare SQL while ignoring prose: thirteen committed
-- migrations already differ from what was applied **only in their comment
-- blocks**, because `apply_migration` takes SQL inline and earlier sessions
-- passed the statements without the long headers the files carry. Hashing raw
-- text reports those as thirteen mismatches on every run, and a check that
-- cries wolf thirteen times is a check nobody reads.
--
-- Normalising has to happen somewhere. It happens in check-drift.mjs, in one
-- place, applied identically to both sides — rather than reimplemented here in
-- SQL, which would be the same rule with two homes and is the shape that has
-- already cost this repo four bugs.
--
-- Returning the text rather than a hash does not widen anything meaningful:
-- this repository is public, so the migrations are readable on GitHub already,
-- and they carry no credentials — `.env` has never been tracked and no key
-- literal exists anywhere in history.
--
-- Adding a column to a return table is not a `create or replace`; Postgres
-- refuses to change a return type, so the old signature is dropped and the
-- revoke/grant pair reissued.

drop function if exists public.migration_ledger();

create function public.migration_ledger()
returns table (version text, statements_md5 text, statements_text text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    m.version,
    md5(array_to_string(m.statements, E'\n')),
    array_to_string(m.statements, E'\n')
  from supabase_migrations.schema_migrations m
  order by m.version;
$$;

comment on function public.migration_ledger() is
  'Applied migration versions with their SQL and an md5 of it, so a local '
  'script can prove the repository and the project agree. Read-only, no user '
  'data, and the statements are public in the repo already. Used by '
  'supabase/check-drift.mjs, which compares SQL with comments stripped so that '
  'a prose-only difference is reported as a note rather than as drift.';

revoke execute on function public.migration_ledger() from public;
grant execute on function public.migration_ledger() to anon, authenticated;
