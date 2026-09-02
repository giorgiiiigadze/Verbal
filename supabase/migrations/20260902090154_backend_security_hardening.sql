-- Security hardening: reserve costly Edge Function work atomically, bound
-- anonymous feedback payloads, and remove PostgreSQL's implicit PUBLIC execute
-- privilege from user-only RPCs.

create table public.request_budget_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  operation text not null check (operation in ('extract_quote', 'verify_subscription')),
  created_at timestamptz not null default now()
);

create index request_budget_reservations_user_operation_created_idx
  on public.request_budget_reservations (user_id, operation, created_at desc);

alter table public.request_budget_reservations enable row level security;
revoke all on public.request_budget_reservations from public, anon, authenticated;

-- A count followed by a later insert is racy: concurrent requests can all see
-- room and each start expensive work. This function locks one user/operation
-- pair, counts the existing reservations, and writes the new one in the same
-- transaction. Reservations deliberately count failed work too: the resource
-- has already been spent by the time a model or verifier returns an error.
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

alter table public.account_deletion_feedback
  add constraint account_deletion_feedback_reason_length
    check (char_length(btrim(reason)) between 1 and 160),
  add constraint account_deletion_feedback_comment_length
    check (comment is null or char_length(comment) <= 2000);

-- PostgreSQL grants EXECUTE to PUBLIC by default. These RPCs authenticate or
-- rely on RLS internally, but should still be unreachable to anonymous users.
revoke execute on function public.create_quote_with_details(
  text, text, text[], text, numeric, numeric, text, text, uuid, jsonb, text
) from public, anon;
grant execute on function public.create_quote_with_details(
  text, text, text[], text, numeric, numeric, text, text, uuid, jsonb, text
) to authenticated;

revoke execute on function public.ensure_share_token(uuid) from public, anon;
grant execute on function public.ensure_share_token(uuid) to authenticated;

revoke execute on function public.revoke_share_token(uuid) from public, anon;
grant execute on function public.revoke_share_token(uuid) to authenticated;

revoke execute on function public.void_quote_usage(uuid) from public, anon;
grant execute on function public.void_quote_usage(uuid) to authenticated;
