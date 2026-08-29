-- A valid Apple signature proves that Apple sold a subscription, not which
-- Verbal account may use it. This table records that ownership once, keyed on
-- Apple's stable original transaction id, so the same subscription chain can
-- never elevate a second Verbal account.
create table public.subscription_owners (
  original_transaction_id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.subscription_owners is
  'The Verbal account that owns each Apple subscription chain. Written only by verify-subscription after Apple signature verification.';

create index subscription_owners_user_id_idx
  on public.subscription_owners (user_id);

alter table public.subscription_owners enable row level security;

-- No client policy: a caller must not be able to discover, claim, or move an
-- Apple subscription. The Edge Function uses service_role after verification.
revoke all on public.subscription_owners from anon, authenticated;

-- RLS decides which records a signed-in user may touch, but Postgres table
-- privileges decide whether the Data API may reach a table at all. A fresh
-- local Supabase project grants only DELETE/TRUNCATE/REFERENCES by default,
-- which made the app's ordinary reads and writes fail before RLS could apply.
-- Keep internal tables above private; these are the user-owned tables the app
-- actually accesses.
grant select on public.profiles to authenticated;
grant select on public.quote_usage to authenticated;
grant select, insert on public.account_deletion_feedback to authenticated;
grant select, insert, update, delete on
  public.business_profiles,
  public.rate_card_items,
  public.customers,
  public.quotes,
  public.quote_line_items,
  public.transcripts,
  public.scheduled_visits
to authenticated;

-- Atomically claim an unbound legacy subscription, or confirm that a renewal
-- still belongs to the same account. This avoids a read-then-insert race when
-- two accounts submit the same signed transaction at once.
create or replace function public.claim_subscription_owner(
  p_original_transaction_id text,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
begin
  if nullif(btrim(p_original_transaction_id), '') is null or p_user_id is null then
    return false;
  end if;

  insert into public.subscription_owners (original_transaction_id, user_id)
  values (p_original_transaction_id, p_user_id)
  on conflict (original_transaction_id) do nothing;

  select user_id into owner_id
    from public.subscription_owners
   where original_transaction_id = p_original_transaction_id;

  return owner_id = p_user_id;
end;
$$;

revoke execute on function public.claim_subscription_owner(text, uuid) from public, anon, authenticated;
grant execute on function public.claim_subscription_owner(text, uuid) to service_role;
