-- Bound the rate limiter's own table.
--
-- `request_budget_reservations` is scratch, not a ledger: nothing ever reads a
-- row older than the 24-hour window, and `usage_events` is where the durable
-- record of a call already lives. Left alone the table grows by one row per
-- extraction forever — 150 a day per user, none of it ever consulted again.
--
-- The prune happens inside `reserve_request_budget` rather than on a schedule
-- because the function has already taken the advisory lock for this exact
-- user/operation pair, so the delete is uncontended, touches only that user's
-- rows, and rides the index that is about to be scanned anyway. A cron job
-- would need its own lock and would be one more thing to notice had stopped.
--
-- Only the body changes below; limits, ordering, and return values are as they
-- were in 20260902090154_backend_security_hardening.sql.

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
  if p_user_id is null or p_operation not in ('extract_quote', 'verify_subscription') then
    raise exception 'Invalid request budget';
  end if;

  if p_operation = 'extract_quote' then
    hourly_limit := 30;
    daily_limit := 150;
  else
    hourly_limit := 12;
    daily_limit := 60;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || p_operation, 0));

  -- Everything past the widest window this function consults. Deleted under the
  -- lock and before the counts, so the numbers below are unchanged by it.
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

-- One-off sweep for rows already past the window, including any belonging to
-- users who never come back and so would never trigger the prune above.
delete from public.request_budget_reservations
 where created_at <= now() - interval '24 hours';
