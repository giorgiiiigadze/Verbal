-- Let a quote be pinned to the top of the list.
-- Recovered from the remote migration history on 2026-08-02; applied to
-- project rglpwlmkwukezvexyups on 2026-07-29.

alter table public.quotes
  add column if not exists pinned boolean not null default false;

create index if not exists quotes_user_pinned_idx
  on public.quotes (user_id, pinned);
