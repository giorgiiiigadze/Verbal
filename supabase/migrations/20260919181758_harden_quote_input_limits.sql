-- Bound the authenticated quote-creation APIs just as the line-item editing
-- API is bounded. RLS protects whose data is touched; these checks protect the
-- database from one legitimate account sending an impractically large payload.

create or replace function public.create_quote_with_details(
  p_title text,
  p_job_summary text,
  p_scope text[],
  p_notes text,
  p_subtotal numeric,
  p_tax_rate numeric,
  p_status text,
  p_currency text,
  p_customer_id uuid,
  p_line_items jsonb,
  p_transcript text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  new_quote_id uuid;
  item jsonb;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_status not in ('draft', 'sent', 'viewed', 'accepted', 'declined', 'expired') then
    raise exception 'Invalid quote status';
  end if;
  if jsonb_typeof(coalesce(p_line_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_line_items, '[]'::jsonb)) > 500 then
    raise exception 'Too many line items';
  end if;
  if coalesce(char_length(p_title), 0) > 250
     or coalesce(char_length(p_job_summary), 0) > 10000
     or coalesce(char_length(p_notes), 0) > 10000
     or coalesce(char_length(p_transcript), 0) > 24000
     or coalesce(cardinality(p_scope), 0) > 100
     or exists (select 1 from unnest(coalesce(p_scope, '{}'::text[])) as scope_item where char_length(scope_item) > 1000) then
    raise exception 'Quote text is too long';
  end if;
  if coalesce(p_tax_rate, 0) < 0 or coalesce(p_tax_rate, 0) > 100 then
    raise exception 'Invalid tax rate';
  end if;
  if coalesce(nullif(btrim(p_currency), ''), 'USD') not in ('USD', 'EUR', 'GBP', 'CAD', 'AUD', 'CHF', 'JPY', 'INR', 'AED') then
    raise exception 'Invalid currency';
  end if;
  if p_customer_id is not null and not exists (
    select 1 from public.customers where id = p_customer_id and user_id = auth.uid()
  ) then raise exception 'Customer not found'; end if;

  insert into public.quotes (user_id, customer_id, title, job_summary, scope, notes, subtotal, tax_rate, status, currency)
  values (auth.uid(), p_customer_id, nullif(btrim(p_title), ''), p_job_summary,
          coalesce(p_scope, '{}'), p_notes, coalesce(p_subtotal, 0), coalesce(p_tax_rate, 0), p_status,
          coalesce(nullif(btrim(p_currency), ''), 'USD'))
  returning id into new_quote_id;

  for item in select * from jsonb_array_elements(coalesce(p_line_items, '[]'::jsonb)) loop
    if jsonb_typeof(item) <> 'object'
       or coalesce(char_length(item->>'description'), 0) > 500
       or coalesce(char_length(item->>'unit'), 0) > 50 then
      raise exception 'Invalid line item';
    end if;
    insert into public.quote_line_items (quote_id, description, type, quantity, unit, unit_price, price_source, confidence, position)
    values (new_quote_id, item->>'description', coalesce(nullif(item->>'type', ''), 'material'),
            nullif(item->>'quantity', '')::numeric, nullif(item->>'unit', ''),
            nullif(item->>'unit_price', '')::numeric, nullif(item->>'price_source', ''),
            nullif(item->>'confidence', ''), coalesce(nullif(item->>'position', '')::integer, 0));
  end loop;

  insert into public.transcripts (quote_id, text, stt_source, status)
  values (new_quote_id, p_transcript, 'on_device', 'done');
  return new_quote_id;
end;
$$;

create or replace function public.create_quote_with_client_details(
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
  if caller_id is null then raise exception 'Not signed in'; end if;
  if p_status not in ('draft', 'sent', 'viewed', 'accepted', 'declined', 'expired') then
    raise exception 'Invalid quote status';
  end if;
  if jsonb_typeof(coalesce(p_line_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_line_items, '[]'::jsonb)) > 500 then
    raise exception 'Too many line items';
  end if;
  if coalesce(char_length(p_title), 0) > 250
     or coalesce(char_length(p_job_summary), 0) > 10000
     or coalesce(char_length(p_notes), 0) > 10000
     or coalesce(char_length(p_transcript), 0) > 24000
     or coalesce(char_length(customer_name), 0) > 250
     or coalesce(cardinality(p_scope), 0) > 100
     or exists (select 1 from unnest(coalesce(p_scope, '{}'::text[])) as scope_item where char_length(scope_item) > 1000) then
    raise exception 'Quote text is too long';
  end if;
  if coalesce(p_tax_rate, 0) < 0 or coalesce(p_tax_rate, 0) > 100 then
    raise exception 'Invalid tax rate';
  end if;
  if coalesce(nullif(btrim(p_currency), ''), 'USD') not in ('USD', 'EUR', 'GBP', 'CAD', 'AUD', 'CHF', 'JPY', 'INR', 'AED') then
    raise exception 'Invalid currency';
  end if;

  if customer_name is not null then
    select id into resolved_customer_id from public.customers
     where user_id = caller_id and lower(name) = lower(customer_name)
     order by updated_at desc, id limit 1;
    if resolved_customer_id is null then
      insert into public.customers (user_id, name) values (caller_id, customer_name)
      returning id into resolved_customer_id;
    end if;
  end if;

  insert into public.quotes (user_id, customer_id, title, job_summary, scope, notes, subtotal, tax_rate, status, currency)
  values (caller_id, resolved_customer_id, nullif(btrim(p_title), ''), p_job_summary,
          coalesce(p_scope, '{}'), p_notes, coalesce(p_subtotal, 0), coalesce(p_tax_rate, 0), p_status,
          coalesce(nullif(btrim(p_currency), ''), 'USD'))
  returning id into new_quote_id;

  for item in select * from jsonb_array_elements(coalesce(p_line_items, '[]'::jsonb)) loop
    if jsonb_typeof(item) <> 'object'
       or coalesce(char_length(item->>'description'), 0) > 500
       or coalesce(char_length(item->>'unit'), 0) > 50 then
      raise exception 'Invalid line item';
    end if;
    insert into public.quote_line_items (quote_id, description, type, quantity, unit, unit_price, price_source, confidence, position)
    values (new_quote_id, item->>'description', coalesce(nullif(item->>'type', ''), 'material'),
            nullif(item->>'quantity', '')::numeric, nullif(item->>'unit', ''),
            nullif(item->>'unit_price', '')::numeric, nullif(item->>'price_source', ''),
            nullif(item->>'confidence', ''), coalesce(nullif(item->>'position', '')::integer, 0));
  end loop;

  insert into public.transcripts (quote_id, text, stt_source, status)
  values (new_quote_id, p_transcript, 'on_device', 'done');
  return new_quote_id;
end;
$$;

revoke execute on function public.create_quote_with_details(
  text, text, text[], text, numeric, numeric, text, text, uuid, jsonb, text
) from public, anon;
grant execute on function public.create_quote_with_details(
  text, text, text[], text, numeric, numeric, text, text, uuid, jsonb, text
) to authenticated;

revoke execute on function public.create_quote_with_client_details(
  text, text, text[], text, numeric, numeric, text, text, text, jsonb, text
) from public, anon;
grant execute on function public.create_quote_with_client_details(
  text, text, text[], text, numeric, numeric, text, text, text, jsonb, text
) to authenticated;
