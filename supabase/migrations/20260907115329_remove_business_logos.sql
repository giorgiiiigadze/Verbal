-- The retired business-logos bucket was deleted through Supabase Storage.
-- Remove its access policies and the profile reference.
drop policy if exists "business logos are publicly readable" on storage.objects;
drop policy if exists "users insert their own business logo" on storage.objects;
drop policy if exists "users update their own business logo" on storage.objects;
drop policy if exists "users delete their own business logo" on storage.objects;

alter table public.business_profiles drop column if exists logo_url;
