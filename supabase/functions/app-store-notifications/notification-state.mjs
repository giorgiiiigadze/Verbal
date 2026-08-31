// The subscription-access decision made from already verified App Store data.
// Kept independent of the HTTP handler so expiry, cancellation, refund and
// grace-period rules can run as fast deterministic tests.

import { PRO_PRODUCT_IDS, bestEntitlement } from "../verify-subscription/entitlement.mjs";

/**
 * @param {{ productId?: string, expiresDate?: number, revocationDate?: number }} transaction
 * @param {{ status?: number } | undefined} data
 * @param {{ gracePeriodExpiresDate?: number } | null} renewal
 * @param {number} now
 */
export function notificationSubscriptionState(transaction, data, renewal, now = Date.now()) {
  const normal = bestEntitlement([transaction], now);
  // App Store status 4 is billing grace. It is access only until the signed
  // renewal-info grace expiry; billing retry is intentionally not access.
  if (data?.status === 4
      && PRO_PRODUCT_IDS.includes(transaction?.productId ?? "")
      && transaction?.revocationDate == null
      && typeof renewal?.gracePeriodExpiresDate === "number"
      && renewal.gracePeriodExpiresDate > now) {
    return {
      status: "grace",
      expiresAt: new Date(renewal.gracePeriodExpiresDate).toISOString(),
      productId: transaction.productId,
    };
  }
  return normal;
}
