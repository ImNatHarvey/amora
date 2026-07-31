-- Hardening: stop exposing rls_auto_enable() through the REST API.
--
-- public.rls_auto_enable() backs the `ensure_rls` event trigger, which enables
-- RLS automatically on any new table in the public schema. It predates this
-- migration and is worth keeping — it is a safety net for CLAUDE.md invariant 6.
--
-- The problem is only that it is a SECURITY DEFINER function which anon and
-- authenticated could reach at /rest/v1/rpc/rls_auto_enable, which Supabase's
-- security linter flags (lints 0028 and 0029). Revoking EXECUTE closes that
-- surface. It does not affect the event trigger: event triggers run as their
-- owner and do not consult EXECUTE grants.
revoke execute on function public.rls_auto_enable() from anon, authenticated;
revoke execute on function public.rls_auto_enable() from public;
