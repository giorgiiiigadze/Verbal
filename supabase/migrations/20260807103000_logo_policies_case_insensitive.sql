-- Compare the folder name to the caller's id case-insensitively.
--
-- Swift renders a UUID in uppercase and Postgres renders one in lowercase, so
-- `(storage.foldername(name))[1] = auth.uid()::text` was false for every upload
-- the app made. RLS denied it, and the app reported "couldn't save your logo" —
-- a correct message about the wrong thing.
--
-- The client now sends the lowercase form, which is the canonical one. This
-- makes the policy stop caring either way, so the next caller to send the other
-- case gets a working upload rather than a permission error that reads like a
-- bug in the feature.

drop policy if exists "users insert their own business logo" on storage.objects;
create policy "users insert their own business logo"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'business-logos'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

drop policy if exists "users update their own business logo" on storage.objects;
create policy "users update their own business logo"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'business-logos'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

drop policy if exists "users delete their own business logo" on storage.objects;
create policy "users delete their own business logo"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'business-logos'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );
