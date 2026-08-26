-- Keep quote creation all-or-nothing. The app used to insert the quote, then
-- line items, then transcript from separate requests; any later failure left a
-- partial draft behind. One RPC runs in one Postgres transaction.

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
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  if p_status not in ('draft', 'sent', 'viewed', 'accepted', 'declined', 'expired') then
    raise exception 'Invalid quote status';
  end if;

  if p_customer_id is not null and not exists (
    select 1
      from public.customers
     where id = p_customer_id
       and user_id = auth.uid()
  ) then
    raise exception 'Customer not found';
  end if;

  insert into public.quotes (
    user_id,
    customer_id,
    title,
    job_summary,
    scope,
    notes,
    subtotal,
    tax_rate,
    status,
    currency
  )
  values (
    auth.uid(),
    p_customer_id,
    nullif(btrim(p_title), ''),
    p_job_summary,
    coalesce(p_scope, '{}'),
    p_notes,
    coalesce(p_subtotal, 0),
    coalesce(p_tax_rate, 0),
    p_status,
    coalesce(nullif(btrim(p_currency), ''), 'USD')
  )
  returning id into new_quote_id;

  for item in select * from jsonb_array_elements(coalesce(p_line_items, '[]'::jsonb))
  loop
    insert into public.quote_line_items (
      quote_id,
      description,
      type,
      quantity,
      unit,
      unit_price,
      price_source,
      confidence,
      position
    )
    values (
      new_quote_id,
      item->>'description',
      coalesce(nullif(item->>'type', ''), 'material'),
      nullif(item->>'quantity', '')::numeric,
      nullif(item->>'unit', ''),
      nullif(item->>'unit_price', '')::numeric,
      nullif(item->>'price_source', ''),
      nullif(item->>'confidence', ''),
      coalesce(nullif(item->>'position', '')::integer, 0)
    );
  end loop;

  insert into public.transcripts (quote_id, text, stt_source, status)
  values (new_quote_id, p_transcript, 'on_device', 'done');

  return new_quote_id;
end;
$$;

revoke execute on function public.create_quote_with_details(
  text, text, text[], text, numeric, numeric, text, text, uuid, jsonb, text
) from anon;
grant execute on function public.create_quote_with_details(
  text, text, text[], text, numeric, numeric, text, text, uuid, jsonb, text
) to authenticated;

-- Share links are bearer credentials. Keep them revocable and avoid making old
-- links valid forever.

alter table public.quotes
  add column if not exists share_token_created_at timestamptz,
  add column if not exists share_token_expires_at timestamptz,
  add column if not exists share_token_revoked_at timestamptz;

create or replace function public.ensure_share_token(quote_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  token text;
begin
  select share_token into token
    from public.quotes
   where id = quote_id
     and share_token is not null
     and share_token_revoked_at is null
     and (
       share_token_expires_at is null
       or share_token_expires_at > now()
     );

  if token is not null then
    return token;
  end if;

  token := replace(gen_random_uuid()::text, '-', '');

  update public.quotes
     set share_token = token,
         share_token_created_at = now(),
         share_token_expires_at = now() + interval '90 days',
         share_token_revoked_at = null
   where id = quote_id;

  if not found then
    raise exception 'Quote not found';
  end if;

  return token;
end;
$$;

revoke execute on function public.ensure_share_token(uuid) from anon;
grant execute on function public.ensure_share_token(uuid) to authenticated;

create or replace function public.revoke_share_token(quote_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.quotes
     set share_token_revoked_at = now()
   where id = quote_id
     and share_token is not null;

  if not found then
    raise exception 'Quote not found';
  end if;
end;
$$;

revoke execute on function public.revoke_share_token(uuid) from anon;
grant execute on function public.revoke_share_token(uuid) to authenticated;
