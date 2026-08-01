-- Why people leave. Deliberately holds no user reference: the row has to
-- outlive the account it came from, and the reason is more useful anonymous
-- than tied to someone who asked to be forgotten.
-- Applied to project rglpwlmkwukezvexyups on 2026-07-31.

create table if not exists public.account_deletion_feedback (
  id uuid primary key default gen_random_uuid(),
  reason text not null,
  comment text,
  created_at timestamptz not null default now()
);

alter table public.account_deletion_feedback enable row level security;

-- Signed-in users may leave feedback and nothing else; reading it is for the
-- service role (dashboard) only.
drop policy if exists "insert own deletion feedback" on public.account_deletion_feedback;
create policy "insert own deletion feedback"
  on public.account_deletion_feedback
  for insert
  to authenticated
  with check (true);
