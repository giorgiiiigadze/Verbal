-- A visit gets a name, a client, and a length.
--
-- `title` used to carry all three jobs at once: it was the client's name, the
-- description of the job, and the label on the card, written as one free-text
-- line. That was right when a visit was a note-to-self, and wrong as soon as
-- the sheet asking for it grew a client field of its own — you cannot match a
-- visit to a client record when the same column might hold "Mrs. Patel" or
-- "bathroom rip-out Thursday".
--
-- So `title` narrows to one meaning — the quote's name — and the client moves
-- out into a column that only ever holds a person.

alter table public.scheduled_visits
  add column client_name text,
  -- How long the visit is booked for. A visit has always had a start and never
  -- an end, which meant two bookings an hour apart looked identical to two
  -- bookings a day apart. 60 minutes for rows written before the column
  -- existed: an hour is the length of nearly every survey, and a wrong default
  -- that is editable beats a null the calendar has to guess at.
  add column duration_minutes integer not null default 60;

comment on column public.scheduled_visits.title is
  'What the visit is called — the quote''s name. Held the client''s name before clients got a column of their own; rows written then still read correctly, because the name of a visit to Mrs. Patel is a reasonable thing to call "Mrs. Patel".';

comment on column public.scheduled_visits.client_name is
  'Who the visit is for. Free text rather than a reference: a visit is booked before there is a customer row to point at.';
