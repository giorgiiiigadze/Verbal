-- Quote numbers were allocated with an unlocked `max(number::int) + 1`, while
-- `quotes_user_number_key` enforces uniqueness. Two inserts for the same user —
-- the draft banked in the background after a recording plus a duplicate tapped
-- from Home, or two devices — read the same maximum, computed the same next
-- value, and the second insert was rejected. In the banking path that error is
-- swallowed, so the quote the user had just dictated silently never existed.
--
-- A transaction-scoped advisory lock keyed on the user serializes allocation
-- per account without taking a lock on the table itself. Unchanged otherwise.

create or replace function public.set_quote_defaults()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  next_num int;
  days int;
begin
  if new.number is null then
    -- Held until the transaction ends, so the reader below and the insert that
    -- follows it can't be interleaved with another quote for the same user.
    perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

    select coalesce(max(number::int), 0) + 1
      into next_num
      from public.quotes
     where user_id = new.user_id
       and number ~ '^[0-9]+$';
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
