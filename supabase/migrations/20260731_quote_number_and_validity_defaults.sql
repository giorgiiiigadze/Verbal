-- Sequential per-user quote numbers and a validity date, filled server-side so
-- every quote gets them regardless of which client created it.
-- Applied to project rglpwlmkwukezvexyups on 2026-07-31.

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

revoke execute on function public.set_quote_defaults() from anon, authenticated;

drop trigger if exists set_quote_defaults_before_insert on public.quotes;
create trigger set_quote_defaults_before_insert
before insert on public.quotes
for each row execute function public.set_quote_defaults();

-- Backfill existing rows: number in creation order per user, validity from the
-- quote's own creation date.
with numbered as (
  select id, row_number() over (partition by user_id order by created_at) as rn
    from public.quotes
   where number is null
)
update public.quotes q
   set number = lpad(n.rn::text, 4, '0')
  from numbered n
 where q.id = n.id;

update public.quotes q
   set validity_date = q.created_at::date + coalesce(
         (select bp.default_validity_days
            from public.business_profiles bp
           where bp.user_id = q.user_id), 14)
 where q.validity_date is null;

-- Two quotes from the same user must never share a number.
create unique index if not exists quotes_user_number_key
  on public.quotes (user_id, number);
