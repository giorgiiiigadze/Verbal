import assert from "node:assert";
import { notificationSubscriptionState } from "./notification-state.mjs";

const NOW = Date.parse("2026-08-31T12:00:00Z");
const HOUR = 60 * 60 * 1_000;
const MONTHLY = "com.giorgi.verbal.pro.monthly";

let passed = 0;
function ok(condition, label) {
  assert.ok(condition, `FAIL  ${label}`);
  console.log(`PASS  ${label}`);
  passed += 1;
}

const active = notificationSubscriptionState(
  { productId: MONTHLY, expiresDate: NOW + 30 * 24 * HOUR }, { status: 1 }, null, NOW,
);
ok(active.status === "active", "a renewal keeps the subscription active");

const cancelledStillPaid = notificationSubscriptionState(
  { productId: MONTHLY, expiresDate: NOW + 24 * HOUR }, { status: 1 }, null, NOW,
);
ok(cancelledStillPaid.status === "active", "cancellation keeps access through the paid expiry");

const expired = notificationSubscriptionState(
  { productId: MONTHLY, expiresDate: NOW - 1 }, { status: 2 }, null, NOW,
);
ok(expired.status === "none", "an expired subscription loses access");

const refunded = notificationSubscriptionState(
  { productId: MONTHLY, expiresDate: NOW + 24 * HOUR, revocationDate: NOW - 1 }, { status: 5 }, null, NOW,
);
ok(refunded.status === "none", "a refunded subscription loses access immediately");

const grace = notificationSubscriptionState(
  { productId: MONTHLY, expiresDate: NOW - 1 }, { status: 4 },
  { gracePeriodExpiresDate: NOW + 3 * HOUR }, NOW,
);
ok(grace.status === "grace", "Apple grace period keeps access until its signed end");

const graceEnded = notificationSubscriptionState(
  { productId: MONTHLY, expiresDate: NOW - 1 }, { status: 4 },
  { gracePeriodExpiresDate: NOW - 1 }, NOW,
);
ok(graceEnded.status === "none", "ended grace period does not retain access");

console.log(`\n${passed} assertions passed`);
