-- Pin search_path and prevent the trigger helpers from being called via RPC.
-- Recovered from the remote migration history on 2026-08-02; applied to
-- project rglpwlmkwukezvexyups on 2026-07-26.

alter function public.handle_updated_at() set search_path = '';

revoke execute on function public.handle_updated_at() from anon, authenticated;
revoke execute on function public.handle_new_user() from anon, authenticated;
