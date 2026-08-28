// Tests for the half of verify-subscription that decides what a verified
// transaction means.
//
//   cd supabase/functions/verify-subscription
//   npm install @apple/app-store-server-library && node entitlement.test.mjs
//
// The signature checking itself is Apple's library's and is not re-tested here,
// with one exception: the last two cases confirm that something which fails
// verification comes back as a rejection rather than as a decoded subscription.
// That is the direction this endpoint has to be wrong in, and it is the only
// thing standing between a patched client and a free Pro tier.

import assert from "node:assert";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { bestEntitlement } from "./entitlement.mjs";
import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";

const NOW = Date.parse("2026-08-28T12:00:00Z");
const FUTURE = NOW + 30 * 86_400_000;
const PAST = NOW - 86_400_000;
const MONTHLY = "com.giorgi.verbal.pro.monthly";
const YEARLY = "com.giorgi.verbal.pro.yearly";

let passed = 0;
function ok(condition, label) {
  assert.ok(condition, "FAIL  " + label);
  console.log("PASS  " + label);
  passed += 1;
}

ok(bestEntitlement([], NOW).status === "none", "no transactions means no subscription");
ok(bestEntitlement(null, NOW).status === "none", "a missing list means no subscription");
ok(bestEntitlement([{ productId: MONTHLY, expiresDate: FUTURE }], NOW).status === "active",
  "a live monthly subscription is active");
ok(bestEntitlement([{ productId: MONTHLY, expiresDate: PAST }], NOW).status === "none",
  "an expired subscription is not active");
ok(bestEntitlement([{ productId: MONTHLY, expiresDate: FUTURE, revocationDate: PAST }], NOW).status === "none",
  "a refunded subscription is not active even though Apple signed it");
ok(bestEntitlement([{ productId: "com.someone.else.pro", expiresDate: FUTURE }], NOW).status === "none",
  "a genuine transaction for another app's product grants nothing");
ok(bestEntitlement([{ productId: MONTHLY }], NOW).status === "none",
  "a transaction with no expiry grants nothing");
ok(bestEntitlement([{ productId: MONTHLY, expiresDate: NOW }], NOW).status === "none",
  "an entitlement expiring exactly now is over");

const upgrade = bestEntitlement([
  { productId: MONTHLY, expiresDate: NOW + 86_400_000 },
  { productId: YEARLY, expiresDate: FUTURE },
], NOW);
ok(upgrade.productId === YEARLY && upgrade.expiresAt === new Date(FUTURE).toISOString(),
  "mid-upgrade, the furthest-future entitlement wins");

// Anything that cannot be verified must come back as a rejection. The verifier
// is built against a root certificate that is not Apple's, which is the closest
// a test can get to "someone else signed this".
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "verbal-jws-"));
const certPath = path.join(dir, "root.der");
execFileSync("openssl", [
  "req", "-x509", "-newkey", "rsa:2048",
  "-keyout", path.join(dir, "key.pem"), "-out", certPath,
  "-days", "2", "-nodes", "-subj", "/CN=not-apple", "-outform", "DER",
], { stdio: "ignore" });

const verifier = new SignedDataVerifier(
  [fs.readFileSync(certPath)], false, Environment.SANDBOX, "com.giorgi.verbal",
);

const b64 = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
const forged = `${b64({ alg: "ES256", x5c: [] })}.${b64({ productId: MONTHLY, expiresDate: FUTURE })}.AAAA`;

for (const [input, label] of [
  [forged, "a self-made 'transaction' claiming a subscription is rejected, not decoded"],
  ["not-a-jws", "garbage input is rejected rather than escaping the handler"],
]) {
  let rejected = false;
  try {
    await verifier.verifyAndDecodeTransaction(input);
  } catch {
    rejected = true;
  }
  ok(rejected, label);
}

fs.rmSync(dir, { recursive: true, force: true });
console.log(`\n${passed} assertions passed`);
