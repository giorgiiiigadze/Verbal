# RevenueCat setup

The SDK is installed in StoreKit 2 observer mode. Verbal continues to purchase,
finish, and verify transactions through `Store` and `SubscriptionService`.
RevenueCat stays disabled when `REVENUECAT_API_KEY` is empty.

When the Apple Developer and RevenueCat accounts are ready:

1. Create the RevenueCat Apple app for bundle ID `com.giorgi.verbal`.
2. Add products `com.giorgi.verbal.pro.monthly` and
   `com.giorgi.verbal.pro.yearly`.
3. Attach both products to entitlement `pro` and a `default` offering.
4. Configure the App Store Connect In-App Purchase key in RevenueCat.
5. Set the public Apple SDK key as the `REVENUECAT_API_KEY` build setting for
   Debug and Release. Never put a RevenueCat secret key in the app.
6. Run a sandbox purchase and confirm the Supabase UUID appears as the RevenueCat
   App User ID and the transaction appears in the dashboard.

Before making RevenueCat authoritative, replace the StoreKit product, purchase,
restore, and entitlement calls together and update the Supabase verification
contract. Do not switch only one side of that boundary.
