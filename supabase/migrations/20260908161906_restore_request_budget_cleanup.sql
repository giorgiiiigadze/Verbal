-- Restore the bounded-retention behavior that the transcription-budget
-- migration accidentally omitted when it replaced this function.
create or replace function public.reserve_request_budget(
  p_user_id uuid,
  p_operation text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  hourly_limit integer;
  daily_limit integer;
  used_hour integer;
  used_day integer;
begin
  if p_user_id is null
     or p_operation not in ('extract_quote', 'transcribe_audio', 'verify_subscription') then
    raise exception 'Invalid request budget';
  end if;

  if p_operation in ('extract_quote', 'transcribe_audio') then
    hourly_limit := 30;
    daily_limit := 150;
  else
    hourly_limit := 12;
    daily_limit := 60;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_operation, 0));

  delete from public.request_budget_reservations
   where user_id = p_user_id
     and operation = p_operation
     and created_at <= now() - interval '24 hours';

  select count(*) into used_hour
    from public.request_budget_reservations
   where user_id = p_user_id
     and operation = p_operation
     and created_at > now() - interval '1 hour';
  if used_hour >= hourly_limit then return 'hour'; end if;

  select count(*) into used_day
    from public.request_budget_reservations
   where user_id = p_user_id
     and operation = p_operation
     and created_at > now() - interval '24 hours';
  if used_day >= daily_limit then return 'day'; end if;

  insert into public.request_budget_reservations (user_id, operation)
  values (p_user_id, p_operation);
  return null;
end;
$$;

revoke execute on function public.reserve_request_budget(uuid, text) from public, anon, authenticated;
grant execute on function public.reserve_request_budget(uuid, text) to service_role;

-- Also reclaim stale rows for users who do not return to trigger the cleanup.
delete from public.request_budget_reservations
 where created_at <= now() - interval '24 hours';
