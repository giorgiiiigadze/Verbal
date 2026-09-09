-- Resolve (or create) the customer and save the complete quote in one
-- transaction. A customer lookup/insert failure therefore cannot degrade into
-- a successful clientless quote.
create function public.create_quote_with_client_details(
  p_title text,
  p_job_summary text,
  p_scope text[],
  p_notes text,
  p_subtotal numeric,
  p_tax_rate numeric,
  p_status text,
  p_currency text,
  p_customer_name text,
  p_line_items jsonb,
  p_transcript text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  customer_name text := nullif(btrim(p_customer_name), '');
  resolved_customer_id uuid;
  new_quote_id uuid;
  item jsonb;
begin
  if caller_id is null then
    raise exception 'Not signed in';
  end if;

  if p_status not in ('draft', 'sent', 'viewed', 'accepted', 'declined', 'expired') then
    raise exception 'Invalid quote status';
  end if;

  if customer_name is not null then
    select id into resolved_customer_id
      from public.customers
     where user_id = caller_id
       and lower(name) = lower(customer_name)
     order by updated_at desc, id
     limit 1;

    if resolved_customer_id is null then
      insert into public.customers (user_id, name)
      values (caller_id, customer_name)
      returning id into resolved_customer_id;
    end if;
  end if;

  insert into public.quotes (
    user_id, customer_id, title, job_summary, scope, notes,
    subtotal, tax_rate, status, currency
  ) values (
    caller_id, resolved_customer_id, nullif(btrim(p_title), ''), p_job_summary,
    coalesce(p_scope, '{}'), p_notes, coalesce(p_subtotal, 0),
    coalesce(p_tax_rate, 0), p_status,
    coalesce(nullif(btrim(p_currency), ''), 'USD')
  ) returning id into new_quote_id;

  for item in select * from jsonb_array_elements(coalesce(p_line_items, '[]'::jsonb))
  loop
    insert into public.quote_line_items (
      quote_id, description, type, quantity, unit, unit_price,
      price_source, confidence, position
    ) values (
      new_quote_id, item->>'description',
      coalesce(nullif(item->>'type', ''), 'material'),
      nullif(item->>'quantity', '')::numeric, nullif(item->>'unit', ''),
      nullif(item->>'unit_price', '')::numeric, nullif(item->>'price_source', ''),
      nullif(item->>'confidence', ''),
      coalesce(nullif(item->>'position', '')::integer, 0)
    );
  end loop;

  insert into public.transcripts (quote_id, text, stt_source, status)
  values (new_quote_id, p_transcript, 'on_device', 'done');

  return new_quote_id;
end;
$$;

revoke all on function public.create_quote_with_client_details(
  text, text, text[], text, numeric, numeric, text, text, text, jsonb, text
) from public;
grant execute on function public.create_quote_with_client_details(
  text, text, text[], text, numeric, numeric, text, text, text, jsonb, text
) to authenticated;
