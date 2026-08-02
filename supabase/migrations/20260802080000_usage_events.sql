-- Per-extraction usage log. Two jobs: replace guessed model costs with measured
-- ones, and give extract-quote a counter to rate-limit against so a single
-- account cannot run up an unbounded OpenAI bill.
--
-- Writes are service-role only. There is deliberately no insert/update/delete
-- policy: if a user could delete their own rows they could reset their own
-- rate limit, which would make the limit decorative.

create table if not exists public.usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  model text not null,
  -- Billed input, split so cached reads (charged at a tenth) stay visible.
  tokens_in integer not null default 0,
  tokens_cached integer not null default 0,
  -- Billed output. Reasoning tokens are a subset of tokens_out, not an addition
  -- to it, but they are worth tracking separately: they are invisible in the
  -- response yet paid for at the output rate.
  tokens_out integer not null default 0,
  tokens_reasoning integer not null default 0,
  cost_usd numeric(12,8) not null default 0,
  duration_ms integer,
  outcome text not null default 'ok'
    check (outcome in ('ok', 'rate_limited', 'model_error'))
);

comment on table public.usage_events
  is 'One row per extract-quote call. Service-role writes only; users may read their own.';

-- The rate-limit query is always "this user, since this timestamp".
create index if not exists usage_events_user_created_idx
  on public.usage_events (user_id, created_at desc);

alter table public.usage_events enable row level security;

create policy "owner_select" on public.usage_events
  for select using ((select auth.uid()) = user_id);
