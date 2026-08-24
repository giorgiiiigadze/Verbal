-- The ledger's rule is that making a quote spends allowance and deleting one
-- never hands it back, because a delete between two quotes would turn two a day
-- into as many as you like. That rule is right, and this does not change it.
--
-- What it misses is re-recording. Generating banks a draft immediately, so
-- someone who records, dislikes the result and records again has spent both of
-- their free quotes before they have one they would send. The ledger counted
-- two quotes; the user made one and is looking at it.
--
-- So this voids exactly one row: a draft the caller owns, made minutes ago,
-- being replaced right now. An old quote deleted still refunds nothing — the
-- fifteen-minute window is what separates "I am still writing this one" from
-- "I am tidying up my list".

create or replace function public.void_quote_usage(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.quote_usage
  where quote_id = p_quote_id
    and user_id = (select auth.uid())
    and created_at > now() - interval '15 minutes';
end;
$$;

-- Definer rights, so it can delete from a table with no delete policy at all —
-- and narrowed by `auth.uid()` inside, so it can only ever reach the caller's
-- own row however it is called.
revoke execute on function public.void_quote_usage(uuid) from anon;
grant execute on function public.void_quote_usage(uuid) to authenticated;
