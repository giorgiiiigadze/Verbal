-- Tax/VAT on quotes. The app supplies subtotal and the rate; the database owns
-- the arithmetic so tax_amount and total can never drift from them.
-- Applied to project rglpwlmkwukezvexyups on 2026-07-31.

alter table public.business_profiles
  add column if not exists default_tax_rate numeric not null default 0;

comment on column public.business_profiles.default_tax_rate
  is 'Percentage, e.g. 20 for 20% VAT. 0 means not tax registered.';

comment on column public.quotes.tax_rate
  is 'Percentage applied to subtotal, copied from the business default when the quote is created.';

create or replace function public.recompute_quote_totals()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.tax_amount := round(coalesce(new.subtotal, 0) * coalesce(new.tax_rate, 0) / 100.0, 2);
  new.total := round(coalesce(new.subtotal, 0) + new.tax_amount, 2);
  return new;
end;
$$;

revoke execute on function public.recompute_quote_totals() from anon, authenticated;

drop trigger if exists recompute_quote_totals_biu on public.quotes;
create trigger recompute_quote_totals_biu
before insert or update of subtotal, tax_rate on public.quotes
for each row execute function public.recompute_quote_totals();
