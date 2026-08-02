-- The customer-facing list of what the job covers, written by the extraction
-- model alongside the line items.
-- Recovered from the remote migration history on 2026-08-02; applied to
-- project rglpwlmkwukezvexyups on 2026-07-30.

alter table public.quotes
  add column if not exists scope text[] not null default '{}';
