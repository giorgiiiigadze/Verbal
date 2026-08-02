-- A short, concrete name for the job, written by the extraction model.
-- Recovered from the remote migration history on 2026-08-02; applied to
-- project rglpwlmkwukezvexyups on 2026-07-26.

alter table public.quotes add column if not exists title text;
