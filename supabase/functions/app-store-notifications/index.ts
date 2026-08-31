// App Store Server Notifications V2 — records subscription changes when the
// customer is not in the app. Apple retries deliveries, and deliveries can be
// out of order, so the database function de-duplicates by notification UUID
// and only lets a newer signed state replace an older one.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.112.2";
import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
import { PRO_PRODUCT_IDS } from "../verify-subscription/entitlement.mjs";
import { notificationSubscriptionState } from "./notification-state.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") ?? "com.giorgi.verbal";
const APP_APPLE_ID = Deno.env.get("APPLE_APP_APPLE_ID");

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

interface DecodedTransaction {
  productId?: string;
  originalTransactionId?: string;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
  signedDate?: number;
}

interface DecodedRenewalInfo {
  gracePeriodExpiresDate?: number;
}

interface DecodedNotification {
  notificationUUID?: string;
  notificationType?: string;
  signedDate?: number;
  data?: {
    status?: number;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function rootCertificates(): Buffer[] {
  return (Deno.env.get("APPLE_ROOT_CERTS") ?? "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => Buffer.from(part, "base64"));
}

function verifiers(certs: Buffer[]): SignedDataVerifier[] {
  const result = [new SignedDataVerifier(certs, true, Environment.SANDBOX, BUNDLE_ID)];
  if (APP_APPLE_ID) {
    result.push(new SignedDataVerifier(
      certs, true, Environment.PRODUCTION, BUNDLE_ID, Number(APP_APPLE_ID),
    ));
  }
  return result;
}

async function verifyNotification(
  signedPayload: string,
  pool: SignedDataVerifier[],
): Promise<{ notification: DecodedNotification; verifier: SignedDataVerifier } | null> {
  for (const verifier of pool) {
    try {
      const notification = await verifier.verifyAndDecodeNotification(signedPayload) as DecodedNotification;
      return { notification, verifier };
    } catch {
      continue;
    }
  }
  return null;
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

/// Resolves ownership only from Apple-signed data. A new transaction carries
/// the appAccountToken set during purchase; older chains are already bound in
/// subscription_owners by verify-subscription.
async function ownerID(transaction: DecodedTransaction): Promise<string | null> {
  const originalID = transaction.originalTransactionId;
  if (!originalID) return null;

  if (transaction.appAccountToken) {
    if (!isUUID(transaction.appAccountToken)) return null;
    const { data, error } = await admin.rpc("claim_subscription_owner", {
      p_original_transaction_id: originalID,
      p_user_id: transaction.appAccountToken,
    });
    if (error) throw error;
    return data === true ? transaction.appAccountToken : null;
  }

  const { data, error } = await admin
    .from("subscription_owners")
    .select("user_id")
    .eq("original_transaction_id", originalID)
    .maybeSingle();
  if (error) throw error;
  return data?.user_id ?? null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const certs = rootCertificates();
  if (certs.length === 0) {
    // Return 503 so Apple retries rather than silently losing subscription
    // changes during a bad deployment. APPLE_APP_APPLE_ID is likewise required
    // for production, but sandbox notifications deliberately work without it.
    console.error("app-store-notifications: Apple verification is not configured");
    return json({ error: "Notification verification is unavailable." }, 503);
  }

  let body: { signedPayload?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (typeof body.signedPayload !== "string" || body.signedPayload.length > 100_000) {
    return json({ error: "Invalid signed payload" }, 400);
  }

  const verified = await verifyNotification(body.signedPayload, verifiers(certs));
  if (!verified) return json({ error: "Invalid notification signature" }, 400);

  const { notification, verifier } = verified;
  const transactionJWS = notification.data?.signedTransactionInfo;
  // TEST and a few summary notifications intentionally carry no transaction.
  // They are still authenticated and should receive a 200 acknowledgement.
  if (!transactionJWS) return json({ received: true });
  if (!notification.notificationUUID || !notification.notificationType) {
    return json({ error: "Notification lacks an identifier" }, 400);
  }

  let transaction: DecodedTransaction;
  let renewal: DecodedRenewalInfo | null = null;
  try {
    // The outer JWS authenticates the notification envelope; Apple requires
    // the nested transaction JWS to be verified independently before use.
    transaction = await verifier.verifyAndDecodeTransaction(transactionJWS) as DecodedTransaction;
    if (notification.data?.signedRenewalInfo) {
      renewal = await verifier.verifyAndDecodeRenewalInfo(
        notification.data.signedRenewalInfo,
      ) as DecodedRenewalInfo;
    }
  } catch {
    return json({ error: "Invalid transaction signature" }, 400);
  }

  if (!transaction.originalTransactionId
      || !PRO_PRODUCT_IDS.includes(transaction.productId ?? "")) {
    return json({ received: true });
  }

  let userID: string | null;
  try {
    userID = await ownerID(transaction);
  } catch (error) {
    console.error("app-store-notifications: owner lookup failed", error);
    return json({ error: "Could not resolve subscription owner" }, 500);
  }
  // A legacy chain may not be associated with an account until that account
  // next opens the app. Acknowledge it: retrying cannot reveal its owner.
  if (!userID) return json({ received: true, owner: "unknown" });

  const state = notificationSubscriptionState(transaction, notification.data, renewal);
  const effectiveAt = new Date(notification.signedDate ?? transaction.signedDate ?? Date.now()).toISOString();
  const { error } = await admin.rpc("record_subscription_state", {
    p_user_id: userID,
    p_status: state.status,
    p_expires_at: state.expiresAt,
    p_product_id: state.productId,
    p_effective_at: effectiveAt,
    p_notification_uuid: notification.notificationUUID,
    p_original_transaction_id: transaction.originalTransactionId,
    p_notification_type: notification.notificationType,
  });
  if (error) {
    console.error("app-store-notifications: state write failed", error.message);
    return json({ error: "Could not record subscription" }, 500);
  }

  return json({ received: true });
});
