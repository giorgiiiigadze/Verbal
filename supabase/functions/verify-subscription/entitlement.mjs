// What a set of verified transactions adds up to.
//
// Kept out of index.ts for the same reason extract-quote keeps its prompt in
// prompt.mjs: this is the part with rules in it, and rules that can't be run in
// a test are rules nobody checks. Signature verification is Apple's library's
// job; deciding what the verified payloads mean is this file's, and it is the
// half where a mistake quietly hands out or withholds a subscription.
//
// Both files must be deployed together.

/// The product identifiers this app sells. A transaction for anything else is
/// not an entitlement to Verbal Pro, however genuinely Apple signed it.
export const PRO_PRODUCT_IDS = [
  "com.giorgi.verbal.pro.monthly",
  "com.giorgi.verbal.pro.yearly",
];

/**
 * @param {Array<{productId?: string, expiresDate?: number, revocationDate?: number}>} transactions
 *        Already verified against Apple's signature. Anything that failed
 *        verification must not reach here.
 * @param {number} now epoch millis, injectable so the expiry rules are testable.
 */
export function bestEntitlement(transactions, now = Date.now()) {
  const products = new Set(PRO_PRODUCT_IDS);
  let expiresAt = null;
  let productId = null;

  for (const tx of transactions ?? []) {
    if (!tx || !tx.productId || !products.has(tx.productId)) continue;
    // Refunded or cancelled by Apple. Signed, valid, and not an entitlement —
    // a refunded subscription is the case where trusting the signature alone
    // would keep someone Pro after their money went back.
    if (tx.revocationDate) continue;
    // A subscription always carries an expiry. Something without one is not the
    // product this app sells, whatever its identifier says.
    if (typeof tx.expiresDate !== "number") continue;
    if (tx.expiresDate <= now) continue;
    // The furthest-future expiry wins: someone upgrading from monthly to yearly
    // briefly holds both, and the one that decides whether they are a
    // subscriber tomorrow is the later one.
    if (expiresAt === null || tx.expiresDate > expiresAt) {
      expiresAt = tx.expiresDate;
      productId = tx.productId;
    }
  }

  return expiresAt === null
    ? { status: "none", expiresAt: null, productId: null }
    : { status: "active", expiresAt: new Date(expiresAt).toISOString(), productId };
}
