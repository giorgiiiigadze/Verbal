-- Quote line-item editing and duplication are each one user action. Keep every
-- row they affect in the same Postgres transaction so a dropped connection can
-- never leave behind half an edit or an empty duplicate.

create or replace function public.replace_quote_line_items(
  p_quote_id uuid,
  p_line_items jsonb
)
returns numeric
language plpgsql
security invoker
set search_path = public
as $$
declare
  item jsonb;
  computed_subtotal numeric(12,2) := 0;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  if jsonb_typeof(coalesce(p_line_items, '[]'::jsonb)) <> 'array' then
    raise exception 'Line items must be an array';
  end if;

  if jsonb_array_length(coalesce(p_line_items, '[]'::jsonb)) > 500 then
    raise exception 'Too many line items';
  end if;

  -- The explicit owner check gives a useful error and prevents an empty RLS
  -- delete followed by inserts from looking like a successful edit.
  if not exists (
    select 1 from public.quotes
     where id = p_quote_id and user_id = auth.uid()
  ) then
    raise exception 'Quote not found';
  end if;

  delete from public.quote_line_items where quote_id = p_quote_id;

  for item in
    select value
      from jsonb_array_elements(coalesce(p_line_items, '[]'::jsonb))
           with ordinality as line(value, ordinal)
     order by ordinal
  loop
    insert into public.quote_line_items (
      quote_id, description, type, quantity, unit, unit_price,
      price_source, confidence, position
    ) values (
      p_quote_id,
      nullif(btrim(item->>'description'), ''),
      coalesce(nullif(item->>'type', ''), 'other'),
      nullif(item->>'quantity', '')::numeric,
      nullif(btrim(item->>'unit'), ''),
      nullif(item->>'unit_price', '')::numeric,
      case when nullif(item->>'unit_price', '') is null then 'missing' else 'spoken' end,
      nullif(item->>'confidence', ''),
      coalesce(nullif(item->>'position', '')::integer, 0)
    );

    computed_subtotal := computed_subtotal + coalesce(
      nullif(item->>'quantity', '')::numeric * nullif(item->>'unit_price', '')::numeric,
      0
    );
  end loop;

  update public.quotes
     set subtotal = computed_subtotal
   where id = p_quote_id and user_id = auth.uid();

  return computed_subtotal;
end;
$$;

revoke execute on function public.replace_quote_line_items(uuid, jsonb)
  from public, anon;
grant execute on function public.replace_quote_line_items(uuid, jsonb)
  to authenticated;

create or replace function public.duplicate_quote_with_details(p_quote_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  source_quote public.quotes%rowtype;
  new_quote_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  select * into source_quote
    from public.quotes
   where id = p_quote_id and user_id = auth.uid();

  if not found then
    raise exception 'Quote not found';
  end if;

  insert into public.quotes (
    user_id, title, job_summary, scope, notes, subtotal, tax_rate,
    status, currency, customer_id, pinned
  ) values (
    auth.uid(),
    case
      when coalesce(source_quote.title, '') = '' then source_quote.title
      else source_quote.title || ' (copy)'
    end,
    source_quote.job_summary,
    source_quote.scope,
    source_quote.notes,
    source_quote.subtotal,
    source_quote.tax_rate,
    'draft',
    source_quote.currency,
    null,
    false
  ) returning id into new_quote_id;

  insert into public.quote_line_items (
    quote_id, description, type, quantity, unit, unit_price,
    price_source, confidence, position
  )
  select new_quote_id, description, type, quantity, unit, unit_price,
         price_source, confidence, position
    from public.quote_line_items
   where quote_id = p_quote_id
   order by position, created_at, id;

  insert into public.transcripts (quote_id, text, stt_source, status)
  select new_quote_id, text, stt_source, status
    from public.transcripts
   where quote_id = p_quote_id
   order by created_at desc
   limit 1;

  return new_quote_id;
end;
$$;

revoke execute on function public.duplicate_quote_with_details(uuid)
  from public, anon;
grant execute on function public.duplicate_quote_with_details(uuid)
  to authenticated;
