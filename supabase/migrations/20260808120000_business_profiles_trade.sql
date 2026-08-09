-- The user's trade, asked once during onboarding.
--
-- The extraction function has accepted a `trade_context` since it was written
-- and nothing has ever sent one: the prompt has a slot for the single piece of
-- context that most changes how a transcript reads, and it has always been
-- empty. "Eight of the 20 mil" is cable to an electrician and pipe to a
-- plumber, and the model has been guessing which.

alter table public.business_profiles
  add column if not exists trade text;

comment on column public.business_profiles.trade is
  'The user''s trade (electrician, plumber, …), captured at onboarding. Sent to the extraction function as trade_context so the model reads "8 of the 20 mil" as cable rather than pipe.';
