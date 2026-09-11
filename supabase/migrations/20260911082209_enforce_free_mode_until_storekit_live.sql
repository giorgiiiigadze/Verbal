-- Until the real App Store products and server credentials exist, every
-- account is intentionally on the free plan. Local StoreKit and RevenueCat
-- Test Store transactions are useful UI simulations, but must not create a
-- server-side unlimited entitlement.
alter table public.app_settings
  add column if not exists subscriptions_enabled boolean not null default false;

update public.app_settings
   set subscriptions_enabled = false,
       quota_enforced = true,
       updated_at = now()
 where id;

create index if not exists quotes_user_created_idx
  on public.quotes (user_id, created_at desc);

-- Use the append-only ledger normally. greatest() also counts surviving quote
-- rows so accounts whose older ledger trigger missed writes cannot receive an
-- accidental unlimited allowance. New writes populate both sources.
create or replace function public.effective_quote_usage(
  p_user_id uuid,
  p_since timestamptz
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    (select count(*)::integer
       from public.quote_usage
      where user_id = p_user_id and created_at >= p_since),
    (select count(*)::integer
       from public.quotes
      where user_id = p_user_id and created_at >= p_since)
  );
$$;

revoke execute on function public.effective_quote_usage(uuid, timestamptz)
  from public, anon, authenticated;

create or replace function public.has_active_subscription(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select subscriptions_enabled from public.app_settings where id),
    false
  ) and exists (
    select 1
      from public.profiles
     where id = p_user_id
       and subscription_status in ('active', 'trialing', 'grace')
       and subscription_expires_at > now()
  );
$$;

revoke execute on function public.has_active_subscription(uuid)
  from public, anon, authenticated;

create or replace function public.enforce_quote_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  allowance integer;
begin
  if uid is null then
    return new;
  end if;

  if new.user_id is distinct from uid then
    raise exception 'Quotes can only be created for the signed-in user'
      using errcode = '42501';
  end if;

  if not public.quota_is_enforced() or public.has_active_subscription(uid) then
    return new;
  end if;

  allowance := public.free_quotes_per_day();
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));

  if public.effective_quote_usage(uid, public.user_day_start(uid)) >= allowance
     or public.effective_quote_usage(uid, now() - interval '24 hours') >= allowance * 2 then
    raise exception 'quote_allowance_exhausted'
      using errcode = 'PT402',
            hint = 'Subscribe for unlimited quotes, or try again tomorrow.';
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_quote_quota()
  from public, anon, authenticated;

-- Recreate explicitly so the deployed table cannot retain a missing or
-- disabled trigger from an interrupted earlier rollout.
drop trigger if exists enforce_quote_quota_before_insert on public.quotes;
create trigger enforce_quote_quota_before_insert
before insert on public.quotes
for each row execute function public.enforce_quote_quota();

create or replace function public.quote_allowance()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  allowance integer;
  used integer;
  pro boolean;
begin
  if uid is null then
    raise exception 'Not signed in';
  end if;

  pro := public.has_active_subscription(uid);
  allowance := public.free_quotes_per_day();
  used := public.effective_quote_usage(uid, public.user_day_start(uid));

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
