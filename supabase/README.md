# Backend

Migrations, edge functions, and the tests that hold them to what their comments
claim.

## Deploy order matters once

Two migrations move the free tier from the app to the database:

- `20260828120000_close_quote_integrity_holes.sql`
- `20260828120100_enforce_free_tier_server_side.sql`

The second one refuses a third quote in a day to anyone the database cannot see
a subscription for — and the only thing that writes `profiles.subscription_status`
is the `verify-subscription` function, fed by a build of the app that reports its
StoreKit entitlement. Apply the migration before those two exist and every
subscriber is treated as a free user: the paywall failing closed on exactly the
people who paid to be past it.

So, in order:

1. Set the secrets `verify-subscription` needs (below) and deploy it.
2. Ship the app build that calls it (`SubscriptionService`, wired into
   `Store.refreshEntitlement`).
3. Confirm `subscription_status` is populating for real subscribers.
4. Apply the migrations.

If something goes wrong after step 4, the gate has an off switch that needs no
deploy and no migration:

```sql
update public.app_settings set quota_enforced = false;
```

Quotes go back to being limited only by the app's own check — which is where
they were before any of this — until you set it back to `true`.

## Secrets

| Name | Used by | Notes |
| --- | --- | --- |
| `OPENAI_API_KEY` | `extract-quote` | |
| `APPLE_ROOT_CERTS` | `verify-subscription` | Comma-separated base64 DER of Apple's root CAs, from <https://www.apple.com/certificateauthority/>. The current chain needs *Apple Root CA - G3*. Pinned as a secret rather than fetched at runtime, so the trust anchor is something you chose. |
| `APPLE_BUNDLE_ID` | `verify-subscription` | Defaults to `com.giorgi.verbal`. |
| `APPLE_APP_APPLE_ID` | `verify-subscription` | The numeric App Store id. Sandbox does not need it; Production transactions cannot be verified without it. |

`verify-subscription` returns 503 rather than downgrading anyone when
`APPLE_ROOT_CERTS` is missing — with no trust anchor nothing can verify, and
writing "not subscribed" for every caller would revoke every subscriber at once.

## Tests

Neither suite runs in CI yet; both are a command.

**Database.** Against a local stack, never production — it writes:

```sh
supabase db reset
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" \
  -f supabase/tests/quota_and_integrity.sql
```

32 assertions, each of which failed before the two migrations above and passes
after. They cover the daily gate, the subscription exemption and its lapse, the
allowance refund, derived totals, quote-number allocation, share-token
lifecycle, and the column grants that keep entitlement out of the client's
hands.

**Entitlement rules.** The half of `verify-subscription` that decides what a
verified transaction means:

```sh
cd supabase/functions/verify-subscription
npm install @apple/app-store-server-library
node entitlement.test.mjs
```
