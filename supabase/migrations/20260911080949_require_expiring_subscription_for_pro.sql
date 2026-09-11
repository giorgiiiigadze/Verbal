-- Auto-renewable StoreKit products always have an expiration date. Treating
-- an active status with no expiry as Pro made old/manual development state an
-- unlimited entitlement that could never lapse. Both quote_allowance() and the
-- insert trigger call this helper, so tightening it fixes the pre-record gate
-- and the authoritative database gate together.
create or replace function public.has_active_subscription(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.profiles
     where id = p_user_id
       and subscription_status in ('active', 'trialing', 'grace')
       and subscription_expires_at > now()
  );
$$;

revoke execute on function public.has_active_subscription(uuid)
  from public, anon, authenticated;

-- The emergency switch may have been disabled while StoreKit verification was
-- being built. This rollout is specifically restoring the advertised limit.
insert into public.app_settings (id, quota_enforced, updated_at)
values (true, true, now())
on conflict (id) do update
  set quota_enforced = excluded.quota_enforced,
      updated_at = excluded.updated_at;
