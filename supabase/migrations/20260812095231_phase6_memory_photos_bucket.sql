-- Phase 6 — where a memory's photo lives.
--
-- PRIVATE, not public. A public bucket serves every object to anyone holding
-- the URL, with no auth check at all — and these are photographs of couples on
-- dates, the most personal data in the app. Invariant 6 says a user must not be
-- able to read another user's memories; a public bucket would honour that in
-- Postgres and break it in HTTP. Reading goes through a signed URL instead.
--
-- Path convention: <uid>/<plan_id>-<epoch>.jpg. The first segment being the
-- owner's uid is what the policies below key on, so the layout is not cosmetic
-- — it IS the authorization rule. plan_id makes an orphaned object traceable
-- back to what it belonged to, and the epoch keeps a re-upload from silently
-- overwriting the previous photo of the same plan.
--
-- The size and mime ceilings are a second line, not the first. The client
-- compresses with image_picker's native maxWidth/imageQuality (D7: no new
-- dependency, and flutter_image_compress's Kotlin Gradle Plugin stays out of
-- the build). Targets are ~150 KB. 2 MB here is the guard against a bug or a
-- future refactor uploading originals — a 12 MB phone photo per memory would
-- eat Supabase's free 1 GB in well under a hundred dates, and D7 has no card to
-- fall back on. jpeg only, because that is the one format the picker emits and
-- an allowlist is cheaper than discovering what else got through.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('memory-photos', 'memory-photos', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Policies on storage.objects, scoped to this bucket
--
-- storage.foldername(name) splits the object path; [1] is the first segment,
-- which by the convention above is the owner's uid. Comparing it to auth.uid()
-- is the whole rule: a user may write into their own folder and read from it,
-- and cannot name a path in anyone else's.
--
-- Every policy names the bucket explicitly. storage.objects is one table for
-- every bucket in the project, so a policy that forgot `bucket_id` would apply
-- to buckets that do not exist yet — a future bucket would arrive already
-- readable, which is the kind of hole nobody goes looking for.
--
-- There is no update policy and no delete policy. Deleting a memory's photo
-- from underneath the row that references it leaves a memory pointing at
-- nothing; if deletion is ever wanted it belongs with deleting the memory
-- itself, as one deliberate change. Overwriting is unnecessary because the
-- epoch in the path makes every upload a new object.
-- ---------------------------------------------------------------------------
create policy memory_photos_insert_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'memory-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy memory_photos_select_own
  on storage.objects for select to authenticated
  using (
    bucket_id = 'memory-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
