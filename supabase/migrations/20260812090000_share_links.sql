-- `share_token` has been on `quotes` since the first schema and nothing has
-- ever written it, which is also why no quote could reach the "viewed" status
-- the app displays: there was no way for a customer to view anything.
--
-- A token is minted on demand rather than at insert. Most quotes are never
-- shared, and a link that exists for all of them is a link that can leak from
-- all of them.
--
-- Reading a shared quote stays off row-level security entirely: the policies
-- here remain owner-only, and the edge function serving these links uses the
-- service role. A public select policy would be a policy someone has to get
-- exactly right forever.

-- Who answered, and when. Without this an accepted quote can't be told apart
-- from one the tradesperson ticked themselves, which matters the moment a
-- customer says they never agreed to it.
alter table public.quotes
  add column if not exists decided_at timestamptz;

do $$
begin
  alter table public.quotes
    add column if not exists decided_by text
    check (decided_by in ('customer', 'owner'));
exception
  when duplicate_column then null;
end $$;

-- Mint a share token for a quote, or hand back the one it already has.
--
-- Security INVOKER on purpose: row-level security already knows whose quote
-- this is, so the ownership check isn't written a second time here where it
-- could drift. A caller asking for someone else's quote sees the select return
-- nothing and the update match nothing, and gets an error rather than a token.
--
-- The token is a UUID with its dashes removed — 122 bits, no pgcrypto needed.
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
   where id = quote_id;

  if token is not null then
    return token;
  end if;

  token := replace(gen_random_uuid()::text, '-', '');

  update public.quotes
     set share_token = token
   where id = quote_id;

  if not found then
    raise exception 'Quote not found';
  end if;

  return token;
end;
$$;

revoke execute on function public.ensure_share_token(uuid) from anon;
grant execute on function public.ensure_share_token(uuid) to authenticated;

create index if not exists quotes_share_token_idx on public.quotes (share_token);
