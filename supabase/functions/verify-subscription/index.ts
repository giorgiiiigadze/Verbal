// verify-subscription — turns a StoreKit entitlement into a fact the database
// can act on.
//
// POST { signed_transactions: string[] }  ->  { status, expires_at, product_id }
//
// `profiles.subscription_status` has existed since the first schema with
// nothing writing it, and the client is deliberately not granted update on it:
// "a paywall that the app it gates can write to is not a paywall". This is the
// writer that comment was waiting for, and the database's quota trigger
// (20260828120100) is the reader.
//
// What arrives is not the app's opinion of whether it has paid. It is the
// `jwsRepresentation` of a StoreKit 2 transaction — a JWS signed by Apple,
// carrying a certificate chain up to Apple's own root. A patched client can
// send whatever it likes here and the worst it can do is fail verification: it
// cannot forge a signature it does not have the key for. That is the whole
// reason this endpoint takes a signed blob rather than a boolean.
//
// Required secrets:
//   APPLE_ROOT_CERTS   comma-separated base64 DER of Apple's root CAs. Get them
//                      from https://www.apple.com/certificateauthority/ — the
//                      current chain needs "Apple Root CA - G3". Pinned as a
//                      secret rather than fetched at runtime so the trust
//                      anchor is something you decided, not something the
//                      network handed us.
//   APPLE_BUNDLE_ID    defaults to com.giorgi.verbal
//   APPLE_APP_APPLE_ID the numeric App Store id. Required before Production
//                      transactions can be verified; Sandbox does not need it.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.112.2";
// The Apple library takes DER certificates as Buffers, which Deno provides
// through its node compatibility layer rather than as a global.
import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
// The rules about what the verified payloads mean, kept where they can be run
// by a test. See entitlement.mjs; both files must be deployed together.
import { bestEntitlement } from "./entitlement.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") ?? "com.giorgi.verbal";
const APP_APPLE_ID = Deno.env.get("APPLE_APP_APPLE_ID");

/// More than anyone can hold: two products, and StoreKit returns one current
/// entitlement per product. Anything beyond this is someone seeing how much
/// signature verification they can make us do per request.
const MAX_TRANSACTIONS = 8;
const MAX_BODY_BYTES = 128 * 1024;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function declaredTooLarge(req: Request): boolean {
  const declared = Number(req.headers.get("Content-Length") ?? "");
  return Number.isFinite(declared) && declared > MAX_BODY_BYTES;
}

async function reserveVerification(userId: string): Promise<string | null> {
  const { data, error } = await admin.rpc("reserve_request_budget", {
    p_user_id: userId,
    p_operation: "verify_subscription",
  });
  if (error) {
    console.error("subscription request-budget reservation failed:", error.message);
    return "meter";
  }
  return typeof data === "string" ? data : null;
}

function rootCertificates(): Buffer[] {
  const raw = Deno.env.get("APPLE_ROOT_CERTS") ?? "";
  return raw
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => Buffer.from(part, "base64"));
}

/// A verifier per environment.
///
/// A build can be talking to Sandbox (TestFlight, a development device) or to
/// Production, and the transaction says which — but the verifier is constructed
/// with an environment and rejects anything from the other one. So both are
/// built and tried in turn rather than guessing from the payload, which would
/// mean trusting an unverified field to choose how to verify.
function verifiers(certs: Buffer[]): SignedDataVerifier[] {
  const built: SignedDataVerifier[] = [];
  // Sandbox first: a production transaction fails against it quickly, and
  // during development every transaction is a sandbox one.
  built.push(
    new SignedDataVerifier(certs, true, Environment.SANDBOX, BUNDLE_ID),
  );
  if (APP_APPLE_ID) {
    built.push(
      new SignedDataVerifier(
        certs,
        true,
        Environment.PRODUCTION,
        BUNDLE_ID,
        Number(APP_APPLE_ID),
      ),
    );
  }
  return built;
}

interface DecodedTransaction {
  productId?: string;
  originalTransactionId?: string;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
  bundleId?: string;
  signedDate?: number;
}

function accountTokenMatches(token: string, userId: string): boolean {
  return token.toLowerCase() === userId.toLowerCase();
}

async function belongsToUser(tx: DecodedTransaction, userId: string): Promise<boolean> {
  // Existing subscriptions predate appAccountToken. They get one atomic first
  // claim by original transaction id; renewals of that chain must stay with
  // the account that claimed it.
  if (!tx.originalTransactionId) return false;
  const { data, error } = await admin.rpc("claim_subscription_owner", {
    p_original_transaction_id: tx.originalTransactionId,
    p_user_id: userId,
  });
  if (error) throw error;
  return data === true;
}

/// Verified, or nothing. Every failure path returns null on purpose: the caller
/// treats "we could not prove this" exactly like "there is no subscription",
/// which is the safe direction to be wrong in.
async function verifyOne(
  jws: string,
  pool: SignedDataVerifier[],
): Promise<DecodedTransaction | null> {
  for (const verifier of pool) {
    try {
      return await verifier.verifyAndDecodeTransaction(jws) as DecodedTransaction;
    } catch {
      continue;
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Not signed in" }, 401);

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "Not signed in" }, 401);
  const userId = userData.user.id;

  if (declaredTooLarge(req)) return json({ error: "Request is too large" }, 413);

  const certs = rootCertificates();
  if (certs.length === 0) {
    // Fail loudly rather than quietly downgrading everyone who paid: with no
    // trust anchor nothing can verify, and writing 'none' for every caller
    // would revoke the paywall exemption of every subscriber at once.
    console.error("verify-subscription: APPLE_ROOT_CERTS is not set");
    return json({ error: "Subscription checks are unavailable." }, 503);
  }

  const raw = await req.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
    return json({ error: "Request is too large" }, 413);
  }

  let body: { signed_transactions?: unknown };
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const window = await reserveVerification(userId);
  if (window) {
    const error = window === "meter"
      ? "Subscription checks are temporarily unavailable."
      : "Too many subscription checks. Try again shortly.";
    return json({ error }, window === "meter" ? 503 : 429);
  }

  const submitted = Array.isArray(body.signed_transactions)
    ? body.signed_transactions.filter((v): v is string => typeof v === "string")
      .slice(0, MAX_TRANSACTIONS)
    : [];

  const pool = verifiers(certs);
  const decoded: DecodedTransaction[] = [];
  for (const jws of submitted) {
    const tx = await verifyOne(jws, pool);
    if (tx) decoded.push(tx);
  }

  // A transaction explicitly associated with another Verbal account is not a
  // "no subscription" answer for this account. Reject it without touching the
  // caller's stored entitlement, otherwise a copied JWS could downgrade the
  // account that submitted it as well as fail to upgrade it.
  if (decoded.some((tx) => tx.appAccountToken && !accountTokenMatches(tx.appAccountToken, userId))) {
    return json({ error: "This subscription belongs to another Verbal account." }, 403);
  }

  // An empty list is a real answer, not a missing one: it is what the app sends
  // when StoreKit reports no current entitlements, which is how a cancellation
  // gets recorded.
  const owned: DecodedTransaction[] = [];
  for (const tx of decoded) {
    // Only active Pro transactions need an owner claim. Recording arbitrary,
    // expired transactions would create a claim surface without granting any
    // current entitlement.
    if (bestEntitlement([tx]).status === "active" && await belongsToUser(tx, userId)) {
      owned.push(tx);
    }
  }
  const entitlement = bestEntitlement(owned);

  // The notification receiver may process a refund or renewal while the app
  // is closed. Use Apple’s signed time here too, so an old device report cannot
  // overwrite a newer server notification delivered out of order.
  const signedDates = decoded
    .map((tx) => tx.signedDate)
    .filter((date): date is number => typeof date === "number");
  const effectiveAt = signedDates.length > 0 ? Math.max(...signedDates) : Date.now();
  const { error: writeError } = await admin.rpc("record_subscription_state", {
    p_user_id: userId,
    p_status: entitlement.status,
    p_expires_at: entitlement.expiresAt,
    p_product_id: entitlement.productId,
    p_effective_at: new Date(effectiveAt).toISOString(),
  });

  if (writeError) {
    console.error("verify-subscription write failed", userId, writeError.message);
    return json({ error: "Could not record subscription" }, 500);
  }

  return json({
    status: entitlement.status,
    expires_at: entitlement.expiresAt,
    product_id: entitlement.productId,
  });
});
