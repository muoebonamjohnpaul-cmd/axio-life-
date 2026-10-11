create table if not exists public.public_profile_identities (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) <= 60),
  username text check (username is null or username ~ '^[a-z0-9_]{3,24}$'),
  avatar_path text,
  constraint public_profile_avatar_path_is_owned check (
    avatar_path is null
    or (
      split_part(avatar_path, '/', 1) = user_id::text
      and split_part(avatar_path, '/', 2) like 'profile-%'
      and split_part(avatar_path, '/', 3) = ''
    )
  )
);

alter table public.public_profile_identities enable row level security;

revoke all on table public.public_profile_identities from public, anon, authenticated;
grant select on table public.public_profile_identities to anon, authenticated;
grant insert, update, delete on table public.public_profile_identities to authenticated;

drop policy if exists public_profile_identities_read_opted_in on public.public_profile_identities;
create policy public_profile_identities_read_opted_in
  on public.public_profile_identities
  for select
  to anon, authenticated
  using (true);

drop policy if exists public_profile_identities_insert_own on public.public_profile_identities;
create policy public_profile_identities_insert_own
  on public.public_profile_identities
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists public_profile_identities_update_own on public.public_profile_identities;
create policy public_profile_identities_update_own
  on public.public_profile_identities
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists public_profile_identities_delete_own on public.public_profile_identities;
create policy public_profile_identities_delete_own
  on public.public_profile_identities
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists progress_media_read_public_profile_avatars on storage.objects;
create policy progress_media_read_public_profile_avatars
  on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id = 'progress-media'
    and exists (
      select 1
      from public.public_profile_identities as public_profile
      where public_profile.avatar_path = objects.name
        and (storage.foldername(objects.name))[1] = public_profile.user_id::text
        and storage.filename(objects.name) like 'profile-%'
    )
  );