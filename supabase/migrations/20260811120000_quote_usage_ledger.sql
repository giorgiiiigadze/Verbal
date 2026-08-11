-- A free tier of two quotes a day needs something to count, and counting rows
-- in `quotes` counts the wrong thing: deleting a draft would hand the allowance
-- back, so two quotes a day becomes as many as you like with a delete between
-- them.
--
-- This ledger records that a quote was made, not that one exists. Nothing
-- deletes from it: there is a select policy and no others, and the only writer
-- is the definer trigger below. `quote_id` is deliberately not a foreign key —
-- a cascade from `quotes` is the exact behaviour being avoided.

create table if not exists public.quote_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  quote_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists quote_usage_user_created_idx
  on public.quote_usage (user_id, created_at desc);

alter table public.quote_usage enable row level security;

do $$
begin
  create policy "owner_read" on public.quote_usage
    for select using ((select auth.uid()) = user_id);
exception
  when duplicate_object then null;
end $$;

-- Logging usage must never be able to cost the user their quote. A quote that
-- fails to save because its bookkeeping row failed is a recording thrown away,
-- which is worse than an uncounted quote by a wide margin — so this swallows
-- its own errors and lets the insert through.
create or replace function public.record_quote_usage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    insert into public.quote_usage (user_id, quote_id)
    values (new.user_id, new.id);
  exception
    when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists quotes_record_usage on public.quotes;
create trigger quotes_record_usage
  after insert on public.quotes
  for each row execute function public.record_quote_usage();

revoke execute on function public.record_quote_usage() from anon, authenticated;
