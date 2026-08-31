# Subscription launch checklist

This is the release order for Verbal’s monthly and yearly Apple subscriptions.
Do each check in order. Do not enable the server-side free-tier gate until a
real Sandbox/TestFlight subscriber is visible as `active` in Supabase.

## Current status — 31 August 2026

- [x] StoreKit purchase, restore, and paywall flows are in the app.
- [x] Supabase verification, ownership binding, quota gate, and notification
  handler are in the repository.
- [x] The linked production project (`rglpwlmkwukezvexyups`) has all existing
  migrations applied.
- [ ] `20260831132905_app_store_notifications.sql` is pending deployment.
- [ ] Apple Developer Program / App Store Connect setup is not yet available.

## 1. Create the Apple foundation

- [ ] Enroll in the [Apple Developer Program](https://developer.apple.com/programs/).
- [ ] In App Store Connect, create the **Verbal** app record with bundle ID
  `com.giorgi.verbal`.
- [ ] Copy the numeric **Apple ID** from App Information.
- [ ] Accept Paid Apps, tax, and banking agreements.
- [ ] Create the `Verbal Pro` auto-renewable subscription group.
- [ ] Create these subscriptions exactly — identifiers must not change after
  release:

| Product | Identifier | Offer |
| --- | --- | --- |
| Monthly | `com.giorgi.verbal.pro.monthly` | $19/month, one seven-day free introductory offer |
| Yearly | `com.giorgi.verbal.pro.yearly` | $190/year |

- [ ] Add subscription localization, review screenshot, availability, and
  required App Review metadata.

## 2. Set production secrets

Download Apple Root CA - G3 from [Apple PKI](https://www.apple.com/certificateauthority/).
Save its DER `.cer` file locally, then make its one-line Base64 value:

```sh
openssl x509 -inform DER -in AppleRootCA-G3.cer -outform DER | base64 | tr -d '\n'
```

Run this from the repository root, replacing the two placeholders. Keep the
root value and Apple ID out of Git and out of the iOS app:

```sh
supabase secrets set --project-ref rglpwlmkwukezvexyups \
  APPLE_ROOT_CERTS='<APPLE_ROOT_CA_G3_BASE64_DER>' \
  APPLE_BUNDLE_ID='com.giorgi.verbal' \
  APPLE_APP_APPLE_ID='<NUMERIC_APP_STORE_APPLE_ID>'
```

Confirm only the names appear — never print secret values:

```sh
supabase secrets list --project-ref rglpwlmkwukezvexyups
```

## 3. Test locally first

Docker Desktop must be running. These commands write only to the local
Supabase stack, never production:

```sh
VERBAL_ALLOW_LOCAL_RESET=1 ./scripts/test-backend.sh
```

Expected result: every SQL assertion and every entitlement test passes.

## 4. Deploy Supabase in this order

First confirm the only pending migration is the notifications migration:

```sh
supabase migration list --linked
```

Then deploy. `db push` is safe for the current production state because the
earlier free-tier migrations are already applied; re-check the previous command
before relying on that assumption.

```sh
supabase db push --linked
supabase functions deploy verify-subscription \
  --project-ref rglpwlmkwukezvexyups --use-api
supabase functions deploy app-store-notifications \
  --project-ref rglpwlmkwukezvexyups --no-verify-jwt --use-api
supabase secrets list --project-ref rglpwlmkwukezvexyups
```

The notification endpoint is:

```text
https://rglpwlmkwukezvexyups.supabase.co/functions/v1/app-store-notifications
```

## 5. Connect App Store Connect

- [ ] In App Store Connect, configure **App Store Server Notifications V2**.
- [ ] Use the endpoint above for both Sandbox and Production.
- [ ] Send Apple’s test notification and confirm the function returns HTTP 200
  and logs `received: true`.

## 6. Test with a real Sandbox/TestFlight Apple ID

- [ ] New monthly purchase gets Pro access immediately.
- [ ] New yearly purchase gets Pro access immediately.
- [ ] Monthly free trial behaves as advertised; yearly does not show a trial.
- [ ] Restore Purchases works after reinstall or on a second device.
- [ ] Sign out/in does not transfer a subscription to another Verbal account.
- [ ] Renewal notification keeps the account Pro without opening the app.
- [ ] Cancellation remains Pro until the paid period ends.
- [ ] Refund/revocation removes Pro access.
- [ ] Grace period keeps access until Apple’s grace expiry.
- [ ] A subscriber who is temporarily stale in Supabase can save after the
  app’s forced reconciliation; they are never shown the paywall incorrectly.

In Supabase SQL Editor, check a test account after purchase and after a test
notification:

```sql
select subscription_status, subscription_product_id,
       subscription_expires_at, subscription_updated_at
from public.profiles
where id = '<TEST_USER_UUID>';
```

## 7. Turn on the paid launch

- [ ] Upload the tested build to TestFlight.
- [ ] Add the subscriptions to the App Store version and submit both app and
  subscriptions for review.
- [ ] After real subscribers show `active` in Supabase, confirm the quota gate:

```sql
select quota_enforced from public.app_settings;
```

It must be `true` for the two-quotes-per-day limit to be server-enforced.

## Emergency rollback

If legitimate subscribers are blocked, use Supabase SQL Editor immediately:

```sql
update public.app_settings set quota_enforced = false;
```

This removes the backend cap while preserving all data. Investigate the
notification/function logs, fix the issue, confirm a Sandbox subscriber again,
then turn it back on:

```sql
update public.app_settings set quota_enforced = true;
```
