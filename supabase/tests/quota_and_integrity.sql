-- Regression tests for the rules the schema states and now enforces.
--
-- Every case here failed before 20260828120000/20260828120100 and passes after.
-- The assertions below use a small TAP emitter rather than the pgTAP
-- extension, so they run anywhere with the migrations applied and report
-- correctly through `supabase test db` / pg_prove:
--
--   supabase db reset
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" -f supabase/tests/quota_and_integrity.sql
--
-- The script makes its own accounts under a fixed uuid prefix and removes them
-- on the way out, so it is safe to re-run and safe against a database that has
-- other data in it. It is NOT safe against production: it writes.

\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
\pset footer off

begin;

create temporary table pg_temp.tap_results (
  test_number integer generated always as identity primary key,
  tap_line text not null
) on commit drop;

create or replace function pg_temp.t_ok(cond boolean, label text)
returns void
language plpgsql
security definer
set search_path = pg_temp
as $$
declare
  test_no integer;
begin
  insert into pg_temp.tap_results (tap_line)
  values ('pending')
  returning test_number into test_no;

  update pg_temp.tap_results as result
  set tap_line = format('%s %s - %s', case when cond then 'ok' else 'not ok' end, test_no, label)
  where result.test_number = test_no;

  if not cond then
    raise exception 'FAIL  %', label;
  end if;
end $$;

create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u, true); end $$;

create or replace function pg_temp.uid(n int) returns uuid language sql immutable as $$
  select ('cafe0000-0000-4000-8000-00000000000' || n)::uuid
$$;

-- ------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------
do $$
declare i int;
begin
  for i in 1..7 loop
    insert into auth.users (id, email, raw_user_meta_data)
      values (pg_temp.uid(i), 'quota-test-' || i || '@example.invalid', '{}'::jsonb)
      on conflict (id) do nothing;
    insert into public.business_profiles (user_id) values (pg_temp.uid(i))
      on conflict (user_id) do nothing;
    insert into public.profiles (id) values (pg_temp.uid(i))
      on conflict (id) do nothing;
  end loop;
end $$;

-- ------------------------------------------------------------
-- The free tier is enforced by the database, not by the phone
-- ------------------------------------------------------------
do $$
declare n int;
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(1)::text);
  insert into public.quotes (user_id, job_summary) values (pg_temp.uid(1), 'one');
  insert into public.quotes (user_id, job_summary) values (pg_temp.uid(1), 'two');
  begin
    insert into public.quotes (user_id, job_summary) values (pg_temp.uid(1), 'three');
    raise exception 'FAIL  a third free quote was allowed';
  exception when sqlstate 'PT402' then
    perform pg_temp.t_ok(sqlerrm = 'quote_allowance_exhausted', 'the third free quote is refused');
  end;
  reset role;
  select count(*) into n from public.quotes where user_id = pg_temp.uid(1);
  perform pg_temp.t_ok(n = 2, 'the refused quote left no row behind');
  select coalesce(max(last_number), 0) into n from public.quote_number_counters where user_id = pg_temp.uid(1);
  perform pg_temp.t_ok(n = 2, 'the refused quote burned no quote number');
end $$;
reset role;

-- A verified subscription lifts the cap; a lapsed one does not.
update public.profiles set subscription_status = 'active', subscription_expires_at = now() + interval '30 days'
  where id = pg_temp.uid(2);
update public.profiles set subscription_status = 'active', subscription_expires_at = now() - interval '1 day'
  where id = pg_temp.uid(3);

do $$
declare n int;
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(2)::text);
  for i in 1..5 loop
    insert into public.quotes (user_id, job_summary) values (pg_temp.uid(2), 'pro');
  end loop;
  reset role;
  select count(*) into n from public.quotes where user_id = pg_temp.uid(2);
  perform pg_temp.t_ok(n = 5, 'an active subscription is not capped');

  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(3)::text);
  insert into public.quotes (user_id, job_summary) values (pg_temp.uid(3), 'a');
  insert into public.quotes (user_id, job_summary) values (pg_temp.uid(3), 'b');
  begin
    insert into public.quotes (user_id, job_summary) values (pg_temp.uid(3), 'c');
    raise exception 'FAIL  a lapsed subscription was still exempt';
  exception when sqlstate 'PT402' then
    perform pg_temp.t_ok(true, 'a lapsed subscription is capped again');
  end;
end $$;
reset role;

-- The client may state its timezone, but not its entitlement.
do $$
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(1)::text);
  update public.profiles set time_zone = 'Europe/London' where id = pg_temp.uid(1);
  perform pg_temp.t_ok(true, 'the client may write time_zone');
  begin
    update public.profiles set subscription_status = 'active' where id = pg_temp.uid(1);
    raise exception 'FAIL  the client granted itself a subscription';
  exception when insufficient_privilege then
    perform pg_temp.t_ok(true, 'the client may not write subscription_status');
  end;
end $$;
reset role;

do $$
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(1)::text);
  begin
    update public.profiles set subscription_expires_at = now() + interval '99 years' where id = pg_temp.uid(1);
    raise exception 'FAIL  the client extended its own expiry';
  exception when insufficient_privilege then
    perform pg_temp.t_ok(true, 'the client may not write subscription_expires_at');
  end;
end $$;
reset role;

-- An unrecognised zone must not cost the user their quote.
update public.profiles set time_zone = 'Not/AZone' where id = pg_temp.uid(1);
select pg_temp.t_ok(public.user_day_start(pg_temp.uid(1)) is not null,
                    'a nonsense timezone falls back to UTC rather than failing');
update public.profiles set time_zone = null where id = pg_temp.uid(1);

-- ------------------------------------------------------------
-- The allowance is only refunded for a quote that is actually gone
-- ------------------------------------------------------------
do $$
declare qid uuid; before int; after_keep int; after_delete int;
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(4)::text);
  insert into public.quotes (user_id, job_summary) values (pg_temp.uid(4), 'keep') returning id into qid;
  select count(*) into before from public.quote_usage where user_id = pg_temp.uid(4);

  perform public.void_quote_usage(qid);
  select count(*) into after_keep from public.quote_usage where user_id = pg_temp.uid(4);
  perform pg_temp.t_ok(after_keep = before, 'voiding a quote you still have refunds nothing');

  delete from public.quotes where id = qid;
  perform public.void_quote_usage(qid);
  select count(*) into after_delete from public.quote_usage where user_id = pg_temp.uid(4);
  perform pg_temp.t_ok(after_delete = before - 1, 're-recording still gets its allowance back');
end $$;
reset role;

-- ------------------------------------------------------------
-- Derived columns are derived on every write
-- ------------------------------------------------------------
do $$
declare t numeric; ta numeric;
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(5)::text);
  insert into public.quotes (user_id, job_summary, subtotal, tax_rate) values (pg_temp.uid(5), 'taxed', 100, 20);
  update public.quotes set total = 999999, tax_amount = 999999 where user_id = pg_temp.uid(5);
  select total, tax_amount into t, ta from public.quotes where user_id = pg_temp.uid(5);
  perform pg_temp.t_ok(t = 120 and ta = 20, 'total and tax stay derived from subtotal and rate');
end $$;
reset role;

-- ------------------------------------------------------------
-- Quote numbers come from the counter, never from the caller
-- ------------------------------------------------------------
do $$
declare n text;
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(6)::text);
  insert into public.quotes (user_id, job_summary, number) values (pg_temp.uid(6), 'forged', '9999')
    returning number into n;
  perform pg_temp.t_ok(n = '0001', 'a client-supplied quote number is ignored');
end $$;
reset role;
-- Drop the caller identity too: the whole script runs in one transaction, so a
-- transaction-local jwt claim outlives the block that set it, and this case is
-- specifically about a caller that has none.
select set_config('request.jwt.claim.sub', '', true);
insert into public.quotes (user_id, job_summary, number) values (pg_temp.uid(6), 'restored', '4242');
select pg_temp.t_ok(count(*) = 1, 'the service role may still restore an explicit number')
  from public.quotes where user_id = pg_temp.uid(6) and number = '4242';

-- ------------------------------------------------------------
-- Share tokens
-- ------------------------------------------------------------
do $$
declare qid uuid; first_token text; second_token text;
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(5)::text);
  select id into qid from public.quotes where user_id = pg_temp.uid(5) limit 1;

  perform public.revoke_share_token(qid);
  perform pg_temp.t_ok(true, 'revoking a never-shared quote is a no-op, not an error');

  begin
    perform public.revoke_share_token('99999999-9999-4999-8999-999999999999');
    raise exception 'FAIL  revoked a quote that is not the caller''s';
  exception when others then
    perform pg_temp.t_ok(sqlerrm = 'Quote not found', 'revoking a quote that is not yours still errors');
  end;

  first_token := public.ensure_share_token(qid);
  perform pg_temp.t_ok(public.ensure_share_token(qid) = first_token, 'sharing twice hands back the same live token');

  perform public.revoke_share_token(qid);
  perform pg_temp.t_ok((select share_token_revoked_at is not null from public.quotes where id = qid),
                       'revoking marks the token revoked');

  second_token := public.ensure_share_token(qid);
  perform pg_temp.t_ok(second_token <> first_token, 're-sharing after revocation mints a new token');
  perform pg_temp.t_ok((select share_token_revoked_at is null from public.quotes where id = qid),
                       're-sharing clears the revocation');

  update public.quotes set share_token_expires_at = now() - interval '1 day' where id = qid;
  perform pg_temp.t_ok(public.ensure_share_token(qid) <> second_token,
                       'an expired token is replaced rather than reissued');
end $$;
reset role;

-- ------------------------------------------------------------
-- The transactional RPC is gated identically, and rolls back whole
-- ------------------------------------------------------------
do $$
declare qid uuid; items jsonb; n int;
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(7)::text);
  items := '[{"description":"Socket","type":"material","quantity":"3","unit":"ea","unit_price":"12.50","position":"0"}]'::jsonb;

  qid := public.create_quote_with_details('T','summary',array['a'],'notes',37.50,20,'draft','GBP',null,items,'spoke');
  perform pg_temp.t_ok((select total from public.quotes where id = qid) = 45.00,
                       'the RPC quote is totalled by the database');
  perform public.create_quote_with_details('T2','s',array[]::text[],null,10,0,'draft','GBP',null,'[]'::jsonb,'x');
  begin
    perform public.create_quote_with_details('T3','s',array[]::text[],null,10,0,'draft','GBP',null,items,'x');
    raise exception 'FAIL  the RPC ignored the allowance';
  exception when sqlstate 'PT402' then
    perform pg_temp.t_ok(true, 'the RPC is refused at the same limit as a direct insert');
  end;
  reset role;
  select count(*) into n from public.quotes where user_id = pg_temp.uid(7);
  perform pg_temp.t_ok(n = 2, 'the refused RPC left no partial quote behind');
  select count(*) into n from public.quote_line_items li
    join public.quotes q on q.id = li.quote_id where q.user_id = pg_temp.uid(7);
  perform pg_temp.t_ok(n = 1, 'the refused RPC left no orphan line items');
end $$;
reset role;

-- ------------------------------------------------------------
-- The allowance the app is told matches the one it is held to
-- ------------------------------------------------------------
do $$
declare j json;
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(1)::text);
  j := public.quote_allowance();
  perform pg_temp.t_ok((j->>'used')::int = 2 and (j->>'remaining')::int = 0 and not (j->>'is_pro')::boolean,
                       'quote_allowance reports an exhausted free user');
  perform pg_temp.as_user(pg_temp.uid(2)::text);
  j := public.quote_allowance();
  perform pg_temp.t_ok((j->>'is_pro')::boolean and j->>'remaining' is null,
                       'quote_allowance reports a subscriber as uncapped');
end $$;
reset role;

-- ------------------------------------------------------------
-- The emergency switch works, and is not the client's to touch
-- ------------------------------------------------------------
update public.app_settings set quota_enforced = false;
do $$
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(1)::text);
  insert into public.quotes (user_id, job_summary) values (pg_temp.uid(1), 'switched off');
  perform pg_temp.t_ok(true, 'clearing app_settings.quota_enforced disables the gate');
end $$;
reset role;

update public.app_settings set quota_enforced = true;
do $$
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(1)::text);
  begin
    insert into public.quotes (user_id, job_summary) values (pg_temp.uid(1), 'switched on');
    raise exception 'FAIL  the gate did not come back on';
  exception when sqlstate 'PT402' then
    perform pg_temp.t_ok(true, 'setting it back restores the gate');
  end;

  begin
    perform pg_temp.t_ok((select count(*) from public.app_settings) = 0,
                         'the client cannot read app_settings');
  exception when insufficient_privilege then
    perform pg_temp.t_ok(true, 'the client cannot read app_settings');
  end;

  begin
    update public.app_settings set quota_enforced = false;
    perform pg_temp.t_ok((select quota_enforced from public.app_settings where id) is null,
                         'the client cannot move the switch');
  exception when insufficient_privilege then
    perform pg_temp.t_ok(true, 'the client cannot move the switch');
  end;
end $$;
reset role;
select pg_temp.t_ok((select quota_enforced from public.app_settings where id),
                    'the switch is untouched after the client tried');

-- ------------------------------------------------------------
-- A subscription chain belongs to exactly one Verbal account
-- ------------------------------------------------------------
do $$
begin
  perform pg_temp.t_ok(
    public.claim_subscription_owner('legacy-subscription-chain-1', pg_temp.uid(1)),
    'the first account can claim a legacy subscription chain'
  );
  perform pg_temp.t_ok(
    not public.claim_subscription_owner('legacy-subscription-chain-1', pg_temp.uid(2)),
    'the same subscription chain cannot be claimed by a second account'
  );

  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(1)::text);
  begin
    perform public.claim_subscription_owner('client-claim', pg_temp.uid(1));
    raise exception 'FAIL  a client could claim a subscription chain';
  exception when insufficient_privilege then
    perform pg_temp.t_ok(true, 'only the subscription verifier may claim a chain');
  end;
end $$;
reset role;

-- ------------------------------------------------------------
-- App Store notifications are private, idempotent, and ordered
-- ------------------------------------------------------------
do $$
declare applied boolean;
begin
  applied := public.record_subscription_state(
    pg_temp.uid(4), 'active', now() + interval '30 days',
    'com.giorgi.verbal.pro.monthly', now(),
    'notification-new', 'notification-chain', 'DID_RENEW'
  );
  perform pg_temp.t_ok(applied, 'a fresh verified notification updates its owner');

  applied := public.record_subscription_state(
    pg_temp.uid(4), 'none', null, null, now() + interval '1 hour',
    'notification-new', 'notification-chain', 'EXPIRED'
  );
  perform pg_temp.t_ok(not applied, 'a retried notification is idempotent');
  perform pg_temp.t_ok(
    (select subscription_status = 'active' from public.profiles where id = pg_temp.uid(4)),
    'a duplicate notification cannot overwrite its first result'
  );

  applied := public.record_subscription_state(
    pg_temp.uid(4), 'none', null, null, now() - interval '1 hour',
    'notification-old', 'notification-chain', 'EXPIRED'
  );
  perform pg_temp.t_ok(not applied, 'an older notification cannot overwrite a newer state');

  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(4)::text);
  begin
    perform public.record_subscription_state(
      pg_temp.uid(4), 'none', null, null, now(), null, null, null
    );
    raise exception 'FAIL  a client could record subscription state';
  exception when insufficient_privilege then
    perform pg_temp.t_ok(true, 'only server-side subscription code can record notification state');
  end;
end $$;
reset role;

-- ------------------------------------------------------------
-- Costly server-side operations reserve their rate-limit slot atomically
-- ------------------------------------------------------------
do $$
declare result text; i integer;
begin
  for i in 1..30 loop
    select public.reserve_request_budget(pg_temp.uid(6), 'extract_quote') into result;
    perform pg_temp.t_ok(result is null, 'an extraction slot is reserved below the hourly limit');
  end loop;

  select public.reserve_request_budget(pg_temp.uid(6), 'extract_quote') into result;
  perform pg_temp.t_ok(result = 'hour', 'the next extraction is refused at the hourly limit');

  for i in 1..12 loop
    select public.reserve_request_budget(pg_temp.uid(6), 'verify_subscription') into result;
    perform pg_temp.t_ok(result is null, 'a subscription-check slot is reserved below the hourly limit');
  end loop;
  select public.reserve_request_budget(pg_temp.uid(6), 'verify_subscription') into result;
  perform pg_temp.t_ok(result = 'hour', 'the next subscription check is refused at the hourly limit');

  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(6)::text);
  begin
    perform public.reserve_request_budget(pg_temp.uid(6), 'extract_quote');
    raise exception 'FAIL  a client could reserve a server-side request budget';
  exception when insufficient_privilege then
    perform pg_temp.t_ok(true, 'only service-side code can reserve a request budget');
  end;
end $$;
reset role;

-- Public execute is not suitable for RPCs that modify an account's data.
select pg_temp.t_ok(
  not has_function_privilege('anon', 'public.create_quote_with_details(text, text, text[], text, numeric, numeric, text, text, uuid, jsonb, text)', 'execute')
  and not has_function_privilege('anon', 'public.ensure_share_token(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.revoke_share_token(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.void_quote_usage(uuid)', 'execute'),
  'anonymous callers cannot execute account-mutating RPCs'
);

-- Deletion feedback is anonymous by design, but its stored input is bounded.
do $$
begin
  set local role authenticated;
  perform pg_temp.as_user(pg_temp.uid(1)::text);
  begin
    insert into public.account_deletion_feedback (reason, comment)
    values (repeat('x', 161), null);
    raise exception 'FAIL  oversized deletion-feedback reason was accepted';
  exception when check_violation then
    perform pg_temp.t_ok(true, 'deletion-feedback reasons have a length limit');
  end;

  begin
    insert into public.account_deletion_feedback (reason, comment)
    values ('Other', repeat('x', 2001));
    raise exception 'FAIL  oversized deletion-feedback comment was accepted';
  exception when check_violation then
    perform pg_temp.t_ok(true, 'deletion-feedback comments have a length limit');
  end;
end $$;
reset role;

select format('1..%s', count(*)) from pg_temp.tap_results;
select tap_line from pg_temp.tap_results order by test_number;

rollback;
