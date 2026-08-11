-- Quote numbers were a bare per-user sequence padded to four digits, with no
-- way for a trade to say where their books start or what their references look
-- like. A business that has been going ten years does not want to send its next
-- customer "0001".
--
-- `number` stays bare digits. `quotes_user_number_key` enforces uniqueness on
-- that column and the allocator below reads `max(number::int)` through a
-- `^[0-9]+$` filter, so a prefix stored in there would break both. The prefix is
-- a label the app applies when a quote is shown or printed, never part of the
-- allocated value.

alter table public.business_profiles
  add column if not exists quote_number_prefix text,
  add column if not exists quote_number_start integer not null default 1;

do $$
begin
  alter table public.business_profiles
    add constraint business_profiles_quote_number_start_check
    check (quote_number_start >= 1);
exception
  when duplicate_object then null;
end $$;

-- Unchanged from the serialised version except for the start: same advisory
-- lock, same validity default.
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
  if new.number is null then
    -- Held until the transaction ends, so the reader below and the insert that
    -- follows it can't be interleaved with another quote for the same user.
    perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

    select coalesce(quote_number_start, 1)
      into start_num
      from public.business_profiles
     where user_id = new.user_id;

    select coalesce(max(number::int), 0) + 1
      into next_num
      from public.quotes
     where user_id = new.user_id
       and number ~ '^[0-9]+$';

    -- The start can only lift the first number: once numbering has passed it the
    -- sequence carries on by itself, so lowering it later can't hand out a
    -- number that has already been issued.
    new.number := lpad(greatest(next_num, coalesce(start_num, 1))::text, 4, '0');
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
