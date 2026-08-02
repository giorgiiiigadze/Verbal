-- ============================================================
-- Voice-to-Quote data model (V1) — §8 of the product spec
-- Recovered from the remote migration history on 2026-08-02; applied to
-- project rglpwlmkwukezvexyups on 2026-07-26.
-- ============================================================

-- Extend profiles to cover the "users" fields (subscription, language, settings)
alter table public.profiles
  add column if not exists subscription_status text not null default 'none',
  add column if not exists language text,
  add column if not exists settings jsonb not null default '{}'::jsonb;

-- ------------------------------------------------------------
-- business_profiles (1:1 with a user)
-- ------------------------------------------------------------
create table public.business_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  business_name text,
  logo_url text,
  phone text,
  email text,
  address text,
  tax_number text,
  currency text not null default 'USD',
  default_validity_days integer not null default 14,
  default_terms text,
  default_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- rate_card_items ("price memory")
-- ------------------------------------------------------------
create table public.rate_card_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  unit text,
  unit_price numeric(12,2),
  type text not null default 'material' check (type in ('labor', 'material', 'other')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index rate_card_items_user_id_idx on public.rate_card_items (user_id);

-- ------------------------------------------------------------
-- customers (lightweight CRM)
-- ------------------------------------------------------------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text,
  phone text,
  email text,
  address text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index customers_user_id_idx on public.customers (user_id);

-- ------------------------------------------------------------
-- quotes
-- ------------------------------------------------------------
create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  customer_id uuid references public.customers (id) on delete set null,
  number text,
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'viewed', 'accepted', 'declined', 'expired')),
  currency text not null default 'USD',
  job_summary text,
  notes text,
  subtotal numeric(12,2) not null default 0,
  tax_rate numeric(6,4) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  validity_date date,
  share_token text unique,
  sent_at timestamptz,
  viewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index quotes_user_id_idx on public.quotes (user_id);
create index quotes_customer_id_idx on public.quotes (customer_id);

-- ------------------------------------------------------------
-- quote_line_items
-- ------------------------------------------------------------
create table public.quote_line_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes (id) on delete cascade,
  description text,
  type text not null default 'material' check (type in ('labor', 'material', 'other')),
  quantity numeric(12,3),
  unit text,
  unit_price numeric(12,2),
  price_source text check (price_source in ('spoken', 'rate_card', 'missing')),
  confidence text check (confidence in ('high', 'low')),
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create index quote_line_items_quote_id_idx on public.quote_line_items (quote_id);

-- ------------------------------------------------------------
-- transcripts (offline queue + debugging; audio stays on device)
-- ------------------------------------------------------------
create table public.transcripts (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes (id) on delete cascade,
  text text,
  stt_source text check (stt_source in ('on_device', 'cloud')),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'done', 'failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index transcripts_quote_id_idx on public.transcripts (quote_id);

-- ============================================================
-- updated_at triggers (reuse public.handle_updated_at)
-- ============================================================
create trigger business_profiles_set_updated_at before update on public.business_profiles
  for each row execute function public.handle_updated_at();
create trigger rate_card_items_set_updated_at before update on public.rate_card_items
  for each row execute function public.handle_updated_at();
create trigger customers_set_updated_at before update on public.customers
  for each row execute function public.handle_updated_at();
create trigger quotes_set_updated_at before update on public.quotes
  for each row execute function public.handle_updated_at();
create trigger transcripts_set_updated_at before update on public.transcripts
  for each row execute function public.handle_updated_at();

-- ============================================================
-- Row Level Security — owner-only on everything
-- ============================================================
alter table public.business_profiles enable row level security;
alter table public.rate_card_items enable row level security;
alter table public.customers enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_line_items enable row level security;
alter table public.transcripts enable row level security;

-- Direct-ownership tables (have user_id)
create policy "owner_all" on public.business_profiles
  for all using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "owner_all" on public.rate_card_items
  for all using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "owner_all" on public.customers
  for all using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "owner_all" on public.quotes
  for all using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Child tables — ownership derived from the parent quote
create policy "owner_via_quote" on public.quote_line_items
  for all
  using (exists (select 1 from public.quotes q where q.id = quote_id and q.user_id = (select auth.uid())))
  with check (exists (select 1 from public.quotes q where q.id = quote_id and q.user_id = (select auth.uid())));
create policy "owner_via_quote" on public.transcripts
  for all
  using (exists (select 1 from public.quotes q where q.id = quote_id and q.user_id = (select auth.uid())))
  with check (exists (select 1 from public.quotes q where q.id = quote_id and q.user_id = (select auth.uid())));
