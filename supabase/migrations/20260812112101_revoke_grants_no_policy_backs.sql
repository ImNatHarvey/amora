-- Review pass — make every write privilege match a policy that permits it.
--
-- FOUND BY AUDIT, not by reading. Supabase ships
--
--   alter default privileges in schema public grant all on tables to anon, authenticated
--
-- so every table created in `public` arrives with INSERT, UPDATE, DELETE and
-- TRUNCATE already granted to both roles. Phase 6 hit this once and fixed its own
-- two tables (migration 20260812095956). This is the same query run across the
-- whole schema, which found thirteen more.
--
-- NOTHING WAS EXPLOITABLE, and that must not be overstated:
--
--   * RLS refuses INSERT, UPDATE and DELETE where no policy permits them — the
--     statement matches zero rows and changes nothing.
--   * TRUNCATE is the one that RLS genuinely does not cover: Postgres row
--     security applies to select/insert/update/delete and never to TRUNCATE, so
--     the grant alone decides. But PostgREST has no TRUNCATE endpoint, so
--     reaching it needs a direct Postgres connection with the anon or
--     authenticated role, which nobody has.
--
-- What WAS wrong is that the documentation claimed a layer that did not exist.
-- §5 says the catalogue tables are "world-readable but insert/update only by the
-- owner role", and HANDOFF.md says in as many words **"Do not grant `update` or
-- `delete` on `places`"** — while both were granted. A defence described in prose
-- and absent from the database is worse than a known single layer, because it
-- stops anyone looking.
--
-- The revokes are written per table to match exactly what has no policy behind
-- it, rather than a blanket `revoke all`. A blanket revoke would have taken
-- INSERT from `places` (Phase 5's user-submitted stops), UPDATE from `profiles`
-- (onboarding writes it), and DELETE from `user_resources` (the picker replaces a
-- selection by deleting and reinserting) — breaking three working features to fix
-- a documentation error. Each line below was checked against `pg_policies` and
-- against the Dart that calls it.
--
-- service_role is untouched throughout: the seed importer, both Edge Functions and
-- every migration run as it, and it is not subject to RLS in the first place.

-- ---------------------------------------------------------------------------
-- Reference data: world-readable, written only by the seed importer.
--
-- This is the catalogue — D3's "the data is the moat". These four tables have a
-- select policy and nothing else, which is the correct shape: a user reads them
-- and never writes them. `places` is handled separately below because Phase 5
-- deliberately opened one narrow insert path into it.
-- ---------------------------------------------------------------------------
revoke insert, update, delete, truncate on public.activities       from anon, authenticated;
revoke insert, update, delete, truncate on public.resource_catalog from anon, authenticated;
revoke insert, update, delete, truncate on public.transit_fares    from anon, authenticated;
revoke insert, update, delete, truncate on public.place_notes      from anon, authenticated;

-- ---------------------------------------------------------------------------
-- places — insert stays, and only insert.
--
-- Phase 5's `places_insert_own_submission` pins source, verification_tier and
-- submitted_by_user_id, which is invariant 5 in one expression. Its migration
-- comment already says why update and delete must never be granted: "an update
-- grant would let a user insert a quarantined row and then promote it, which is
-- the same hole through a second door." Both were granted anyway, by default,
-- from the moment the table was created.
-- ---------------------------------------------------------------------------
revoke update, delete, truncate on public.places from anon, authenticated;

-- ---------------------------------------------------------------------------
-- plan_edits — append-only, now at the grant level too.
--
-- Flagged during Phase 6 and deliberately left alone as out-of-phase; this pass
-- is the right scope for it. Its own comment reads "Append-only: there is no
-- update or delete policy, because a log that can be rewritten is not a log" —
-- true of the policies, and until now false of the grants. Invariant 7 depends on
-- this log: if most users delete the same suggested stop, that recommendation is
-- bad, and a log a user could quietly prune could not answer that.
-- ---------------------------------------------------------------------------
revoke update, delete, truncate on public.plan_edits from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Owner-scoped tables: keep every verb a policy permits, drop the rest.
--
-- plans, plan_items and plan_legs need select/insert/update/delete — save_plan
-- and edit_plan are `security invoker`, so they act as the caller and the caller
-- must be able to rewrite their own stop list. Only TRUNCATE is unbacked.
--
-- profiles keeps update (onboarding sets display name, city and onboarded_at) and
-- loses delete, which has no policy: account deletion is on the deferred list, and
-- when it is built it needs a policy written deliberately rather than a grant that
-- was always there.
--
-- user_resources keeps insert and delete — `replaceMine` writes the difference by
-- deleting and inserting rows, never by updating one — and loses update.
-- ---------------------------------------------------------------------------
revoke truncate on public.plans      from anon, authenticated;
revoke truncate on public.plan_items from anon, authenticated;
revoke truncate on public.plan_legs  from anon, authenticated;

revoke delete, truncate on public.profiles from anon, authenticated;

revoke update, truncate on public.user_resources from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The caches: server infrastructure, not user data.
--
-- Both have RLS on with zero policies, which is how Postgres spells "service role
-- only" — the security advisor flags both permanently and HANDOFF.md records that
-- as expected noise rather than a finding. Revoking the grants as well means a
-- device cannot reach them by any verb, not merely by none that RLS permits.
--
-- This matters more than it looks for plan_cache: an attacker who could write it
-- could serve every other user a plan of their choosing, totals and all, with the
-- app rendering it as though Postgres had costed it.
-- ---------------------------------------------------------------------------
revoke insert, update, delete, truncate on public.plan_cache   from anon, authenticated;
revoke insert, update, delete, truncate on public.intake_cache from anon, authenticated;
