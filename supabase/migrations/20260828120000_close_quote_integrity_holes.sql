-- Five places where a rule the schema states in a comment was not actually
-- enforced by the schema. None of them are reachable from the app as written;
-- all of them are reachable from anything else holding the publishable key,
-- which ships in the app binary.

-- ------------------------------------------------------------
-- 1. The allowance refund only applies to a quote that is gone
-- ------------------------------------------------------------
-- `void_quote_usage` was written for one caller: re-recording, which deletes
-- the banked draft and then hands its allowance back. But the function only
-- ever checked that the row was the caller's own and minutes old — never that
-- the quote it belonged to had actually been deleted. Called directly with the
-- id of a quote you are keeping, it returned the allowance and left the quote
-- standing, which is the "delete between two quotes" loophole the ledger was
-- built to close, arrived at from the other direction.
--
-- Requiring the quote to be absent is the whole fix, and it costs the real
-- caller nothing: `discardDraft` already deletes first and voids second.
create or replace function public.void_quote_usage(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.quotes where id = p_quote_id) then
    return;
  end if;

  delete from public.quote_usage
  where quote_id = p_quote_id
    and user_id = (select auth.uid())
    and created_at > now() - interval '15 minutes';
end;
$$;

revoke execute on function public.void_quote_usage(uuid) from anon;
grant execute on function public.void_quote_usage(uuid) to authenticated;

-- ------------------------------------------------------------
-- 2. Totals are derived on every write, not just two columns
-- ------------------------------------------------------------
-- The tax migration said the database owns the arithmetic "so tax_amount and
-- total can never drift". The trigger was `update of subtotal, tax_rate`, so an
-- update naming neither column skipped it — and unlike `profiles`, `quotes` has
-- no column grants, so a client can write `total` directly. The claim held for
-- the paths the app happens to use and nowhere else.
--
-- Firing on every update makes the derived columns genuinely derived: whatever
-- a caller sends for `tax_amount` or `total` is overwritten from `subtotal` and
-- `tax_rate` before it lands.
drop trigger if exists recompute_quote_totals_biu on public.quotes;
create trigger recompute_quote_totals_biu
before insert or update on public.quotes
for each row execute function public.recompute_quote_totals();

-- ------------------------------------------------------------
-- 3. Quote numbers come from the counter, never from the caller
-- ------------------------------------------------------------
-- `set_quote_defaults` allocated only when `new.number is null`, so a client
-- could name its own number. That skips the counter, which then hands the same
-- number out later and trips `quotes_user_number_key` — an account able to
-- wedge its own numbering, and a customer able to hold two different documents
-- with one reference on them.
--
-- Signed-in callers no longer choose. A service-role caller still can, because
-- restoring a backup means writing the numbers the backup has.
create or replace function public.set_quote_defaults()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  next_num int;
  start_num int;
  days int;
begin
  -- auth.uid() is null for the service role and for a direct psql session:
  -- both are restore paths, and both keep the number they were given.
  if auth.uid() is not null then
    new.number := null;
  end if;

  if new.number is null then
    -- Held until the transaction ends, so two quotes for one user can't read
    -- the counter before either of them has written it.
    perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

    select coalesce(quote_number_start, 1)
      into start_num
      from public.business_profiles
     where user_id = new.user_id;

    -- First quote on an account that predates the counter: seed from whatever
    -- its quotes have already reached.
    insert into public.quote_number_counters (user_id, last_number)
    values (
      new.user_id,
      greatest(
        coalesce((select max(number::int)
                    from public.quotes
                   where user_id = new.user_id
                     and number ~ '^[0-9]+$'), 0),
        coalesce(start_num, 1) - 1
      )
    )
    on conflict (user_id) do nothing;

    -- The start is a floor, not a reset: it can lift numbering while the
    -- counter is still below it, and is ignored once numbering has passed it,
    -- so lowering it later can never reissue a number.
    update public.quote_number_counters
       set last_number = greatest(last_number + 1, coalesce(start_num, 1)),
           updated_at = now()
     where user_id = new.user_id
    returning last_number into next_num;

    new.number := lpad(next_num::text, 4, '0');
  end if;

  if new.validity_date is null then
    select default_validity_days
      into days
      from public.business_profiles
     where user_id = new.user_id;
    new.validity_date := current_date + coalesce(days, 14);
  end if;

  return new;
end;
$$;

revoke execute on function public.set_quote_defaults() from public, anon, authenticated;

-- ------------------------------------------------------------
-- 4. "Never shared" is not "not found"
-- ------------------------------------------------------------
-- `revoke_share_token` matched on `share_token is not null`, so revoking a
-- quote that had never been shared raised "Quote not found" about a quote that
-- is right there. Revoking nothing is the correct outcome and already the
-- state the caller asked for; only a quote that genuinely isn't theirs is an
-- error. Row-level security is what decides which of the two it is.
create or replace function public.revoke_share_token(quote_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not exists (select 1 from public.quotes q where q.id = quote_id) then
    raise exception 'Quote not found';
  end if;

  update public.quotes
     set share_token_revoked_at = now()
   where id = quote_id
     and share_token is not null
     and share_token_revoked_at is null;
end;
$$;

revoke execute on function public.revoke_share_token(uuid) from anon;
grant execute on function public.revoke_share_token(uuid) to authenticated;

-- ------------------------------------------------------------
-- 5. Deleting a quote shouldn't scan every visit
-- ------------------------------------------------------------
-- `recorded_quote_id` is `on delete set null`, and Postgres does not index the
-- referencing side for you, so each quote delete was a sequential scan of
-- scheduled_visits. Trivial at today's row counts and free to fix now.
create index if not exists scheduled_visits_recorded_quote_idx
  on public.scheduled_visits (recorded_quote_id)
  where recorded_quote_id is not null;
