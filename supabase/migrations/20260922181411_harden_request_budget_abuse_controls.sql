-- Abuse controls for paid Edge Function work.
--
-- These limits are deliberately independent of subscription/quota policy:
-- every authenticated account is bounded before it can invoke OpenAI or
-- AssemblyAI, including an account that has a paid product entitlement.

-- Queries that prune all expired reservations need their own leading-column
-- index. The existing per-user index only helps a cleanup scoped to one user.
create index if not exists request_budget_reservations_created_at_idx
  on public.request_budget_reservations (created_at);

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

  -- The extractor is cheap enough for a productive day, while a transcription
  -- can upload a 25 MB recording and incur a materially higher provider cost.
  -- Neither limit is part of the customer-facing subscription allowance.
  if p_operation = 'extract_quote' then
    hourly_limit := 15;
    daily_limit := 75;
  elsif p_operation = 'transcribe_audio' then
    hourly_limit := 4;
    daily_limit := 20;
  else
    hourly_limit := 12;
    daily_limit := 60;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_operation, 0));

  -- Accounts created solely for abuse do not return to trigger the old
  -- per-account cleanup. Prune globally on every reservation so the table is
  -- bounded without a separately configured cron service.
  delete from public.request_budget_reservations
   where created_at <= now() - interval '24 hours';

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

revoke execute on function public.reserve_request_budget(uuid, text)
  from public, anon, authenticated;
grant execute on function public.reserve_request_budget(uuid, text)
  to service_role;
