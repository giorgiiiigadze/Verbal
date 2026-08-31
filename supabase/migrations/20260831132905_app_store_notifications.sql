-- App Store Server Notifications are delivered more than once and can arrive
-- out of order. Keep each verified notification exactly once, and make the
-- profile update part of the same transaction as that de-duplication.
create table public.app_store_notification_events (
  notification_uuid text primary key,
  original_transaction_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null,
  signed_at timestamptz not null,
  received_at timestamptz not null default now()
);

comment on table public.app_store_notification_events is
  'Verified App Store Server Notifications V2. Private audit/idempotency ledger; written only by app-store-notifications.';

create index app_store_notification_events_user_id_idx
  on public.app_store_notification_events (user_id);

alter table public.app_store_notification_events enable row level security;
revoke all on public.app_store_notification_events from public, anon, authenticated;

-- A client report and a server notification are two sources for the same
-- state. The notification has Apple’s signed timestamp, so an older delivery
-- must not undo a newer renewal, refund, or expiration.
alter table public.profiles
  add column if not exists subscription_updated_at timestamptz;

comment on column public.profiles.subscription_updated_at is
  'Effective time of the most recent Apple-verified subscription state. Prevents out-of-order App Store notifications from overwriting newer state.';

create or replace function public.record_subscription_state(
  p_user_id uuid,
  p_status text,
  p_expires_at timestamptz,
  p_product_id text,
  p_effective_at timestamptz,
  p_notification_uuid text default null,
  p_original_transaction_id text default null,
  p_notification_type text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_count integer := 0;
begin
  if p_user_id is null
     or p_status not in ('active', 'trialing', 'grace', 'none')
     or p_effective_at is null then
    return false;
  end if;

  if p_notification_uuid is not null then
    if nullif(btrim(p_original_transaction_id), '') is null
       or nullif(btrim(p_notification_type), '') is null then
      return false;
    end if;

    insert into public.app_store_notification_events (
      notification_uuid, original_transaction_id, user_id, notification_type, signed_at
    ) values (
      p_notification_uuid, p_original_transaction_id, p_user_id, p_notification_type, p_effective_at
    ) on conflict (notification_uuid) do nothing;

    -- Apple retries until it sees a 2xx. Once an event is recorded, a retry is
    -- already fully handled and must not replay an older state transition.
    if not found then return false; end if;
  end if;

  update public.profiles
     set subscription_status = p_status,
         subscription_expires_at = p_expires_at,
         subscription_product_id = p_product_id,
         subscription_updated_at = p_effective_at
   where id = p_user_id
     and (subscription_updated_at is null or subscription_updated_at <= p_effective_at);

  get diagnostics updated_count = row_count;
  return updated_count > 0;
end;
$$;

revoke execute on function public.record_subscription_state(uuid, text, timestamptz, text, timestamptz, text, text, text)
  from public, anon, authenticated;
grant execute on function public.record_subscription_state(uuid, text, timestamptz, text, timestamptz, text, text, text)
  to service_role;
