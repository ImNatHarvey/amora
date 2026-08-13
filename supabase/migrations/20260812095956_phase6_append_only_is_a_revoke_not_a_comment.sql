-- Phase 6 — make "append-only" true at the grant level, not just at the policy.
--
-- FOUND BY ASSERTION, not by reading. The first migration of this phase says
-- "no update or delete policy, and no grant for either", and wrote
-- `grant select, insert on ... to authenticated` believing that was the whole
-- grant. It was not. Supabase ships
--
--   alter default privileges in schema public grant all on tables to anon, authenticated
--
-- so every table created in `public` arrives with DELETE, UPDATE, TRUNCATE and
-- the rest already granted to both roles. An explicit `grant select, insert` adds
-- nothing and takes nothing away — it reads like a restriction and is a no-op.
--
-- Nothing was exposed. RLS is the real enforcement and it held: with no delete
-- policy, a user deleting their own reports affects zero rows. That was verified
-- as the user, not assumed. But the failure was SILENT — the delete succeeded and
-- removed nothing — and the migration claimed a second layer that did not exist.
-- A defence in a comment is not a defence.
--
-- So: revoke, and let the attempt error loudly instead. Two layers now, and the
-- comment is true.
--
-- Why loud matters here specifically. place_reports is evidence, and 6b ages it.
-- A user who could delete a report could withdraw the record that a place has
-- closed — the one signal §10.2 says we are structurally short of. If some future
-- policy change ever made those rows visible to a delete, the grant is what would
-- decide whether the row survives, and today it would not have.
--
-- anon is revoked too. It cannot pass either policy (auth.uid() is null, so
-- nothing matches), which is exactly the kind of reasoning that is true until
-- someone adds a policy for a signed-out surface. Revoking costs nothing.
--
-- NOT FIXED HERE, and flagged rather than fixed: plan_edits (Phase 5) has the
-- same blanket grants and the same belief written into its comment and into
-- HANDOFF.md. It is protected by RLS in exactly the same way, so it is not a
-- live hole — but it is the same one-line change and it belongs to Phase 5, not
-- to this phase. CLAUDE.md says flag it and wait rather than reach outside the
-- phase, so this migration deliberately leaves it alone.

revoke update, delete, truncate on public.memories      from anon, authenticated;
revoke update, delete, truncate on public.place_reports from anon, authenticated;

-- Restated so the intent survives the revoke above being read on its own.
comment on table public.place_reports is
  'One row per stop of a completed plan, plus standalone closure reports. '
  'Append-only, and enforced twice: no update or delete POLICY (so RLS matches '
  'no rows) and no update or delete GRANT (so the attempt errors). 6b ages these '
  'rows, and a report that can be withdrawn is not evidence.';

comment on table public.memories is
  'One per completed plan. plan_id is unique so a double completion cannot '
  'duplicate the place_reports written beside it, which 6b takes a median over. '
  'Insert-only for now: editing a caption is a real want and needs its own '
  'policy, deliberately written when it is built rather than left ajar here.';
