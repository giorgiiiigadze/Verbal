-- Storage for business logos, printed at the top of every quote a customer sees.
--
-- Public read. The logo is on a document that gets emailed and forwarded to
-- strangers, so treating its bytes as a secret would be pretending. Writes are
-- another matter: a user may only touch objects under a folder named after
-- their own id, so nobody can overwrite or delete someone else's mark.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'business-logos',
  'business-logos',
  true,
  2097152, -- 2 MB. The app downscales before upload; this is the backstop.
  array['image/png', 'image/jpeg']
)
on conflict (id) do nothing;

-- Anyone may read: the rendered quote is shared outside the app.
drop policy if exists "business logos are publicly readable" on storage.objects;
create policy "business logos are publicly readable"
  on storage.objects for select
  using (bucket_id = 'business-logos');

-- Write, replace and remove only within your own folder. `storage.foldername`
-- returns the path segments, so the first one has to be the caller's user id.
drop policy if exists "users insert their own business logo" on storage.objects;
create policy "users insert their own business logo"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'business-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "users update their own business logo" on storage.objects;
create policy "users update their own business logo"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'business-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "users delete their own business logo" on storage.objects;
create policy "users delete their own business logo"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'business-logos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
