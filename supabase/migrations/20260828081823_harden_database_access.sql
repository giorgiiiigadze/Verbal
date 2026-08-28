-- Keep every public function deterministic about the objects it resolves.
-- This is especially important for functions called through the Data API.
alter function public.free_quotes_per_day() set search_path = public;

-- These tables are internal implementation details. The app never reads or
-- writes them directly: quote numbering is maintained by a trigger and the
-- setting is consumed server-side. Make that denial explicit while retaining
-- RLS as a second layer of protection.
create policy "no client access" on public.app_settings
  as permissive
  for all
  to anon, authenticated
  using (false)
  with check (false);

create policy "no client access" on public.quote_number_counters
  as permissive
  for all
  to anon, authenticated
  using (false)
  with check (false);

-- A user may discard the usage row created for a replacement draft, but only
-- for their own unlinked quote and only during the existing fifteen-minute
-- grace period. This replaces elevated function execution with normal RLS.
create policy "owner_void_recent_replaced_quote" on public.quote_usage
  for delete
  to authenticated
  using (
    (select auth.uid()) = user_id
    and created_at > now() - interval '15 minutes'
    and not exists (
      select 1
      from public.quotes
      where quotes.id = quote_usage.quote_id
        and quotes.user_id = (select auth.uid())
    )
  );

create or replace function public.void_quote_usage(p_quote_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  delete from public.quote_usage
  where quote_id = p_quote_id;
end;
$$;

revoke execute on function public.void_quote_usage(uuid) from public, anon;
grant execute on function public.void_quote_usage(uuid) to authenticated;

-- The allowance query only reads rows the caller already owns under RLS, so it
-- does not require SECURITY DEFINER. Its helpers retain their narrow, audited
-- elevated access to the caller's profile row.
create or replace function public.quote_allowance()
returns json
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  uid uuid;
  allowance int;
  used int;
  pro boolean;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'Not signed in';
  end if;

  pro := public.has_active_subscription(uid);
  allowance := public.free_quotes_per_day();

  select count(*) into used
    from public.quote_usage
   where user_id = uid and created_at >= public.user_day_start(uid);

  return json_build_object(
    'is_pro', pro,
    'limit', allowance,
    'used', used,
    'remaining', case when pro then null else greatest(allowance - used, 0) end,
    'resets_at', public.user_day_start(uid) + interval '1 day'
  );
end;
$$;

revoke execute on function public.quote_allowance() from public, anon;
grant execute on function public.quote_allowance() to authenticated;
