-- Create a profiles row automatically whenever an auth user is created.
--
-- Without this, signup and profile creation are two separate client calls, and
-- anything failing between them leaves an auth account with no profile. That
-- account cannot own resources at all, since user_resources.user_id references
-- profiles(id) — so the failure is silent at signup and only surfaces later.
--
-- SECURITY DEFINER because the trigger runs as the signing-up user, who has no
-- rights on public.profiles at that moment. search_path is pinned to empty and
-- every name below is schema-qualified, so the elevated function cannot be
-- redirected by a caller-controlled search_path.
--
-- Only the id is set here. display_name and city are Phase 1's job — this
-- migration exists to guarantee the row exists, not to populate it.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

-- The trigger fires as its owner, so no role needs EXECUTE. Revoking keeps the
-- function off the REST API surface (security linter 0028/0029).
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
