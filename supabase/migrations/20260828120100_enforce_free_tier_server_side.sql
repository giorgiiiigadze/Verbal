-- The free tier was a client-side rule.
--
-- `quote_usage` was written faithfully by a trigger, read by the app, and
-- obeyed by `Store.canCreateQuote` — on the phone. Nothing in the database
-- refused anything. Every reason the ledger exists (deleting a quote must not
-- refund it; the counter must only go up) protected a limit that any caller
-- holding the publishable key could simply decline to apply. The allowance was
-- documented, metered, and optional.
--
-- This moves the decision to the one place that cannot be skipped. The app
-- keeps its own check, because being told "no" before you have spoken for two
-- minutes is much better than being told after — but the app's check is now a
-- courtesy in front of the real one rather than the only one.

-- ------------------------------------------------------------
-- Entitlement, as the server understands it
-- ------------------------------------------------------------
-- `subscription_status` has been on `profiles` since the first schema with
-- nothing writing it, and the client is deliberately not granted update on it
-- (20260802120000) — "a paywall that the app it gates can write to is not a
-- paywall". `verify-subscription` is what fills it in, from a StoreKit
-- transaction verified against Apple's own signature.
--
-- The expiry is stored beside it so a lapsed subscription downgrades itself.
-- Otherwise an account that stops paying stays 'active' until the app next
-- gets a chance to say otherwise, and "the app must call in for the paywall to
-- close" is the same trust that put us here.
alter table public.profiles
  add column if not exists subscription_expires_at timestamptz,
  add column if not exists subscription_product_id text,
  -- The user's own IANA zone, so "two quotes a day" means their day. Written by
  -- the client because that is the only thing that knows; see the cap below for
  -- why being able to lie about it doesn't buy much.
  add column if not exists time_zone text;

comment on column public.profiles.subscription_expires_at is
  'When the verified subscription lapses. Null for a status that has no expiry. Read by quote_allowance(); never written by the client.';

comment on column public.profiles.time_zone is
  'IANA zone (e.g. "Europe/London") reported by the app, so the daily allowance rolls over at the user''s midnight rather than UTC''s.';

-- Column grants decide which columns, row-level security decides which row.
-- `time_zone` joins the list the client may write; the two subscription columns
-- deliberately do not.
grant update (username, full_name, avatar_url, bio, language, settings, onboarded, time_zone)
  on public.profiles to authenticated;

-- ------------------------------------------------------------
-- The allowance
-- ------------------------------------------------------------
create or replace function public.free_quotes_per_day()
returns integer
language sql
immutable
as $$ select 2 $$;

comment on function public.free_quotes_per_day() is
  'The free tier, in one place. SessionStore.freeQuotesPerDay must match.';

revoke execute on function public.free_quotes_per_day() from public, anon, authenticated;

-- Start of the caller's own day, as a timestamptz.
--
-- An unrecognised zone is not worth an error in the middle of saving a quote —
-- it is worth UTC and a quote that saves.
create or replace function public.user_day_start(p_user_id uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
begin
  select nullif(btrim(time_zone), '') into tz
    from public.profiles
   where id = p_user_id;

  begin
    return date_trunc('day', now() at time zone coalesce(tz, 'UTC'))
             at time zone coalesce(tz, 'UTC');
  exception
    when others then
      return date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  end;
end;
$$;

revoke execute on function public.user_day_start(uuid) from public, anon, authenticated;

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
       and (subscription_expires_at is null or subscription_expires_at > now())
  );
$$;

revoke execute on function public.has_active_subscription(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- The gate
-- ------------------------------------------------------------
-- Two counts, and the second is only there because the first one trusts the
-- user's clock.
--
-- The calendar count is what the product promises: two a day, rolling over at
-- your midnight. `time_zone` is client-written, so someone walking their zone
-- eastwards could keep arriving at a fresh midnight. The rolling 24-hour cap
-- bounds that — an honest user never comes near it, because it is twice the
-- allowance they are being offered.
create or replace function public.enforce_quote_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
  allowance int;
  used_today int;
  used_rolling int;
begin
  uid := auth.uid();

  -- No JWT means the service role or a maintenance session, and neither is
  -- spending someone's allowance.
  if uid is null then
    return new;
  end if;

  -- Inserting a quote for somebody else is not a quota question.
  if new.user_id is distinct from uid then
    raise exception 'Quotes can only be created for the signed-in user'
      using errcode = '42501';
  end if;

  if public.has_active_subscription(uid) then
    return new;
  end if;

  allowance := public.free_quotes_per_day();

  -- The same lock `set_quote_defaults` takes, for the same reason: without it
  -- the count below and the ledger row written after this insert can interleave
  -- with another quote for this user, and two simultaneous requests each see
  -- one used and both proceed. Re-taking a lock already held in this
  -- transaction is free.
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));

  select count(*) into used_today
    from public.quote_usage
   where user_id = uid
     and created_at >= public.user_day_start(uid);

  if used_today >= allowance then
    -- PT402 is PostgREST's convention for "answer this with 402". The message
    -- is matched by the client too, so an older gateway that returns it as a
    -- 500 still raises the paywall rather than an apology.
    raise exception 'quote_allowance_exhausted'
      using errcode = 'PT402',
            hint = 'Subscribe for unlimited quotes, or try again tomorrow.';
  end if;

  select count(*) into used_rolling
    from public.quote_usage
   where user_id = uid
     and created_at > now() - interval '24 hours';

  if used_rolling >= allowance * 2 then
    raise exception 'quote_allowance_exhausted'
      using errcode = 'PT402',
            hint = 'Subscribe for unlimited quotes, or try again tomorrow.';
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_quote_quota() from public, anon, authenticated;

-- Named to sort ahead of the other two before-insert triggers, so a quote that
-- is going to be refused is refused before a number is allocated for it. A
-- number handed out inside a transaction that then rolls back is a gap in the
-- user's sequence, and their customers count those.
drop trigger if exists enforce_quote_quota_before_insert on public.quotes;
create trigger enforce_quote_quota_before_insert
before insert on public.quotes
for each row execute function public.enforce_quote_quota();

-- ------------------------------------------------------------
-- What the app asks
-- ------------------------------------------------------------
-- The client used to compute its own local midnight and count rows since then.
-- Now that the server decides, the server also answers — otherwise the two
-- arithmetics drift and the app cheerfully offers an allowance the database
-- refuses.
create or replace function public.quote_allowance()
returns json
language plpgsql
stable
security definer
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
   where user_id = uid
     and created_at >= public.user_day_start(uid);

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

-- ------------------------------------------------------------
-- A switch, because this gate can be wrong in an expensive direction
-- ------------------------------------------------------------
-- Everything above depends on `verify-subscription` having written
-- `subscription_status` for the people who pay. If that function is broken,
-- misconfigured, or simply not deployed yet, every subscriber looks like a free
-- user and gets refused at two quotes a day — the paywall failing closed on the
-- exact people who paid to be past it.
--
-- The ordering that avoids this is: deploy verify-subscription, ship the app
-- build that reports entitlement, confirm `subscription_status` is populating,
-- and only then apply this migration. That ordering is a process, and processes
-- are what you have instead of a switch at 2am. So: a switch.
--
--   update public.app_settings set quota_enforced = false;
--
-- turns the gate off project-wide with no deploy and no migration. It is on by
-- default, because a limit that ships disabled is the thing this file exists to
-- stop being true.
create table if not exists public.app_settings (
  id boolean primary key default true,
  quota_enforced boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint app_settings_single_row check (id)
);

insert into public.app_settings (id) values (true) on conflict (id) do nothing;

-- No policies at all: service role and dashboard only. A client that can read
-- whether it is being enforced against has learned nothing useful; a client
-- that could write it has learned everything.
alter table public.app_settings enable row level security;

create or replace function public.quota_is_enforced()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select quota_enforced from public.app_settings where id), true)
$$;

revoke execute on function public.quota_is_enforced() from public, anon, authenticated;

create or replace function public.enforce_quote_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
  allowance int;
  used_today int;
  used_rolling int;
begin
  uid := auth.uid();

  -- No JWT means the service role or a maintenance session, and neither is
  -- spending someone's allowance.
  if uid is null then
    return new;
  end if;

  -- Inserting a quote for somebody else is not a quota question.
  if new.user_id is distinct from uid then
    raise exception 'Quotes can only be created for the signed-in user'
      using errcode = '42501';
  end if;

  if not public.quota_is_enforced() then
    return new;
  end if;

  if public.has_active_subscription(uid) then
    return new;
  end if;

  allowance := public.free_quotes_per_day();

  -- The same lock `set_quote_defaults` takes, for the same reason: without it
  -- the count below and the ledger row written after this insert can interleave
  -- with another quote for this user, and two simultaneous requests each see
  -- one used and both proceed. Re-taking a lock already held in this
  -- transaction is free.
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));

  select count(*) into used_today
    from public.quote_usage
   where user_id = uid
     and created_at >= public.user_day_start(uid);

  if used_today >= allowance then
    -- PT402 is PostgREST's convention for "answer this with 402". The message
    -- is matched by the client too, so an older gateway that returns it as a
    -- 500 still raises the paywall rather than an apology.
    raise exception 'quote_allowance_exhausted'
      using errcode = 'PT402',
            hint = 'Subscribe for unlimited quotes, or try again tomorrow.';
  end if;

  select count(*) into used_rolling
    from public.quote_usage
   where user_id = uid
     and created_at > now() - interval '24 hours';

  if used_rolling >= allowance * 2 then
    raise exception 'quote_allowance_exhausted'
      using errcode = 'PT402',
            hint = 'Subscribe for unlimited quotes, or try again tomorrow.';
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_quote_quota() from public, anon, authenticated;
