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

For a fresh subscription rollout, first apply
`20260828100822_bind_subscription_ownership.sql` and
`20260831132905_app_store_notifications.sql`; the latter gives both
subscription functions their atomic, ordered state writer. Then, in order:

1. Set the secrets both subscription functions need (below) and deploy them.
2. Configure App Store Server Notifications V2 as described below.
3. Ship the app build that calls it (`SubscriptionService`, wired into
   `Store.refreshEntitlement`).
4. Confirm `subscription_status` is populating for real subscribers.
5. Apply the two free-tier enforcement migrations above.

## App Store Server Notifications V2

The app report above is still useful at sign-in and purchase time, but it
cannot see a renewal, refund, or billing change while the customer does not
open Verbal. `app-store-notifications` receives those changes directly from
Apple and applies them to the same profile state.

Deploy the database migration before either function uses it, then deploy both
functions:

```sh
supabase db push
supabase functions deploy verify-subscription
supabase functions deploy app-store-notifications --no-verify-jwt
```

In App Store Connect, set the **App Store Server Notifications** production and
sandbox URL to:

```
https://rglpwlmkwukezvexyups.supabase.co/functions/v1/app-store-notifications
```

Apple sends a JSON body containing `signedPayload`; it does not send a
Supabase JWT. The endpoint is public only for that reason: it verifies the
outer notification JWS and its nested signed transaction JWS against the
Apple roots before reading or writing subscription state. Invalid signatures
receive 400, while unavailable verification or database writes receive 503/500
so Apple retries them.

`APPLE_ROOT_CERTS`, `APPLE_BUNDLE_ID`, and `APPLE_APP_APPLE_ID` must be set
before production traffic. Sandbox does not require the numeric app id, but
production signature verification does. Do not put these values in the app
binary. Send an App Store Connect test notification after deployment and check
the function logs for a `received: true` response.

If something goes wrong after step 4, the gate has an off switch that needs no
deploy and no migration:

```sql
update public.app_settings set quota_enforced = false;
```

Quotes go back to being limited only by the app's own check — which is where
they were before any of this — until you set it back to `true`.

## Subscription ownership rollout

`20260828100822_bind_subscription_ownership.sql` makes every Apple
subscription chain belong to one Verbal account. Its function is called by the
updated `verify-subscription` edge function, so deploy in this order:

1. Apply the migration. It is inert until the function starts calling it.
2. Deploy `verify-subscription` with the migration.
3. Ship the app build that purchases with StoreKit's `appAccountToken`.

New purchases are bound to the current Verbal account by Apple. Existing
purchases do not have an account token and are claimed once, by the account
that first reports the verified subscription after this rollout.

## Secrets

| Name | Used by | Notes |
| --- | --- | --- |
| `OPENAI_API_KEY` | `extract-quote` | |
| `APPLE_ROOT_CERTS` | `verify-subscription`, `app-store-notifications` | Comma-separated base64 DER of Apple's root CAs, from <https://www.apple.com/certificateauthority/>. The current chain needs *Apple Root CA - G3*. Pinned as a secret rather than fetched at runtime, so the trust anchor is something you chose. |
| `APPLE_BUNDLE_ID` | `verify-subscription`, `app-store-notifications` | Defaults to `com.giorgi.verbal`. |
| `APPLE_APP_APPLE_ID` | `verify-subscription`, `app-store-notifications` | The numeric App Store id. Sandbox does not need it; Production transactions cannot be verified without it. |

`verify-subscription` returns 503 rather than downgrading anyone when
`APPLE_ROOT_CERTS` is missing — with no trust anchor nothing can verify, and
writing "not subscribed" for every caller would revoke every subscriber at once.

## Tests

GitHub Actions runs the notification, entitlement, and database suites on every
pull request and push to `main`. Run the same complete set locally (Docker
Desktop required) with:

```sh
VERBAL_ALLOW_LOCAL_RESET=1 ./scripts/test-backend.sh
```

The opt-in is deliberate: the database test resets the local Supabase stack.

**Database.** Against a local stack, never production — it writes:

```sh
supabase db reset
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" \
  -f supabase/tests/quota_and_integrity.sql
```

The database suite also exercises the request-budget reservation and its
service-role-only permission, anonymous RPC restrictions, and deletion-feedback
input bounds introduced by `20260902090154_backend_security_hardening.sql`.

Each assertion failed before its corresponding migration and passes
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

**Notification rules.** Renewal, cancellation, expiry, refund, and grace
period state after Apple’s outer and nested JWS values have been verified:

```sh
node supabase/functions/app-store-notifications/notification-state.test.mjs
```
