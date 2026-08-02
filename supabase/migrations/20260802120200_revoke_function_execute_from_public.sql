-- 20260726125821 revoked EXECUTE on the trigger helpers from `anon` and
-- `authenticated`, but Postgres grants EXECUTE to PUBLIC when a function is
-- created, and that grant was never touched — `proacl` still showed `=X/postgres`
-- and the security advisor still reported handle_new_user and set_quote_defaults
-- as callable over /rest/v1/rpc/. Revoking from PUBLIC is what actually closes
-- them; the earlier revokes were decorative.
--
-- Triggers are unaffected: a trigger function runs on behalf of the table, and
-- its invocation does not check EXECUTE.

revoke execute on function public.handle_updated_at() from public;
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.set_quote_defaults() from public;

-- Added by the tax migration and never revoked at all.
revoke execute on function public.recompute_quote_totals() from public, anon, authenticated;
