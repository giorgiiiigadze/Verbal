-- Profiles were readable by "everyone": the select policy was `using (true)`
-- for role `public`, and `anon` holds SELECT on the table. The publishable key
-- ships in plain text inside the app binary, so "everyone" meant anyone who
-- unzipped the app and paged through /rest/v1/profiles.
--
-- Nothing in the product reads another user's profile — SessionStore fetches
-- `eq(id, currentUser.id)` and nothing else — so owner-only costs no feature.

drop policy if exists "Profiles are viewable by everyone" on public.profiles;

create policy "Users can view their own profile"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

-- The update policy allows a user to write any column of their own row, and
-- `subscription_status` is exactly the column a paywall would gate on. Column
-- grants keep the profile itself editable while leaving entitlement to the
-- service role: RLS decides which row, these decide which columns.
revoke update on public.profiles from anon, authenticated;
grant update (username, full_name, avatar_url, bio, language, settings, onboarded)
  on public.profiles to authenticated;
