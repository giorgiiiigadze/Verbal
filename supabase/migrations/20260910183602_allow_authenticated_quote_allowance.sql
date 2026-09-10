-- quote_allowance is the authenticated, user-scoped wrapper around private
-- quota helpers. Those helpers deliberately grant EXECUTE only to postgres and
-- service_role, so an invoker-rights wrapper fails with permission denied
-- before it can return the caller's allowance.
--
-- The wrapper reads auth.uid(), refuses a missing identity, and never accepts a
-- user id as input. Running just this wrapper as its owner lets it call the
-- private helpers without making either helper part of the client API.
alter function public.quote_allowance() security definer;

revoke execute on function public.quote_allowance() from public, anon;
grant execute on function public.quote_allowance() to authenticated;
