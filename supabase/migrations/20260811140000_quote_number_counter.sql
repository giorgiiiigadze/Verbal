-- Quote numbers were allocated as `max(number::int) + 1` over the user's own
-- quotes, which means the sequence walks backwards when the newest quote is
-- deleted and hands its number to the next one. While testing that just looks
-- untidy. Once a customer is holding a document it is a real collision: two
-- different quotes, months apart, carrying the same reference, and nothing in
-- either the app or the database saying which one "0021" means.
--
-- Same shape as the free-tier problem, and the same answer: allocate from
-- something that only ever goes up. This counter records the highest number
-- ISSUED, not the highest number still on file, so deleting a quote no longer
-- returns its number to the pool.

create table if not exists public.quote_number_counters (
  user_id uuid primary key references auth.users (id) on delete cascade,
  last_number integer not null default 0,
  updated_at timestamptz not null default now()
);

-- No policies, deliberately. Nothing outside the definer trigger below has any
-- business writing here, and handing a client the ability to move this counter
-- is handing it the ability to reissue a number.
alter table public.quote_number_counters enable row level security;

-- Carry existing accounts across at the number they have actually reached, so
-- numbering continues rather than restarting.
insert into public.quote_number_counters (user_id, last_number)
select user_id, max(number::int)
from public.quotes
where number ~ '^[0-9]+$'
group by user_id
on conflict (user_id) do nothing;

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
    -- Held until the transaction ends, so two quotes for one user can't read
    -- the counter before either of them has written it.
    perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

    select coalesce(quote_number_start, 1)
      into start_num
      from public.business_profiles
     where user_id = new.user_id;

    -- First quote on an account that predates this table: seed from whatever
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
