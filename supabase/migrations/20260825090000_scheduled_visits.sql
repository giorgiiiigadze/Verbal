-- Booked visits — the Upcoming section on Home.
--
-- These lived in a single UserDefaults key on the device, with no user id in
-- it, and sign-out deleted them. Not hid them: deleted. They existed nowhere
-- else, so signing back in on the same phone brought back nothing, and a user
-- who switched accounts lost their booked week permanently.
--
-- A visit is still deliberately not a quote: no customer row, no number, no
-- line items, no total. It is a note-to-self with a date on it. But it belongs
-- to a person rather than a handset, and that is what this table says.

create table public.scheduled_visits (
  -- Supplied by the client, not generated here. A visit booked in a basement
  -- with no signal is written on the device first and pushed later; it has to
  -- keep the same identity across that gap, or the retry inserts it twice.
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  -- One free-text line — "Mrs. Patel — bathroom". Written in the ten seconds
  -- after a phone call, which is why it isn't a form.
  title text not null,
  scheduled_at timestamptz not null,
  phone text,
  address text,
  note text,
  -- Set once the visit has been recorded into a quote. `set null` rather than
  -- cascade: deleting the quote un-links the visit, it does not delete the
  -- booking. That is also what makes a quote deleted on one device release the
  -- visit on another, without the app having to notice.
  recorded_quote_id uuid references public.quotes (id) on delete set null,
  -- The one-time "did this go ahead?" prompt, so a visit that has been asked
  -- about is not asked about again on the next device.
  did_prompt_for_missed_visit boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.scheduled_visits is
  'Visits booked but not yet quoted — Home''s Upcoming section. Written on the device first and synced, so a booking made with no signal is never lost.';

-- Every read is "this user, in time order", which is also how the list is drawn.
create index scheduled_visits_user_scheduled_idx
  on public.scheduled_visits (user_id, scheduled_at);

-- No handle_updated_at trigger here, unlike its neighbours, and on purpose:
-- `updated_at` is written by the client and sent with every upsert, because it
-- is what resolves a conflict between two devices. Server receipt time would
-- let a phone that has been offline for three days overwrite a newer edit made
-- on another one — it arrived last, so it would win. The edit's own timestamp
-- doesn't have that problem.

alter table public.scheduled_visits enable row level security;

create policy "owner_all" on public.scheduled_visits
  for all using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
