-- A quota that allows the quote while silently dropping its ledger entry is
-- not enforced. The old trigger swallowed every insert failure; that was
-- friendly during an outage but created an unlimited-free-quotes path whenever
-- the ledger was misconfigured or unavailable.
create or replace function public.record_quote_usage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.quote_usage (user_id, quote_id)
  values (new.user_id, new.id);
  return new;
end;
$$;

-- Trigger functions are not an API. Revoking PUBLIC matters because anon and
-- authenticated inherit it even after role-specific revokes.
revoke execute on function public.record_quote_usage() from public, anon, authenticated;

-- The transactional quote RPC already checks this, but direct Data API writes
-- are also allowed for offline compatibility. A quote must never point at a
-- customer owned by another account.
create or replace function public.enforce_quote_customer_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.customer_id is not null and not exists (
    select 1
      from public.customers
     where id = new.customer_id
       and user_id = new.user_id
  ) then
    raise exception 'Customer not found' using errcode = '23503';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_quote_customer_ownership_biu on public.quotes;
create trigger enforce_quote_customer_ownership_biu
before insert or update of customer_id, user_id on public.quotes
for each row execute function public.enforce_quote_customer_ownership();

revoke execute on function public.enforce_quote_customer_ownership() from public, anon, authenticated;
