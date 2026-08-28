// quote — the public API behind a share link.
//
// GET  /quote/<token>   the quote as JSON, and marks it viewed
// POST /quote/<token>   { action: "accept" | "decline" }
//
// This returns data, not a page, and the page lives on GitHub Pages. Not a
// preference: Supabase's gateway stamps every function response with
// `content-security-policy: default-src 'none'; sandbox` and rewrites the
// content type to text/plain, so HTML served from *.supabase.co arrives
// unstyled, unscripted, and with forms disabled. Sensible of them — it is a
// shared domain — but it means the customer-facing markup has to be hosted
// somewhere else.
//
// The only function here that runs without a JWT, so every request is treated
// as hostile: the token is the entire credential, shape-checked before the
// database is touched, and the only row it can reach is the one holding that
// exact token. Row-level security stays owner-only; the service role is used
// precisely so no public policy has to exist and stay correct forever.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false, autoRefreshToken: false } },
);

/// 32 hex characters, as minted by `ensure_share_token`. Checked before the
/// database is touched so a malformed token costs a regex rather than a query.
const TOKEN_PATTERN = /^[0-9a-f]{32}$/;

/// The page that renders this. Listed explicitly rather than answering `*`:
/// this endpoint changes quote statuses, and any site being able to call it
/// from a visitor's browser is a wider door than it needs.
const ALLOWED_ORIGINS = [
  "https://giorgiiiigadze.github.io",
];

function allowedOrigin(origin: string | null): string | null {
  if (!origin) return ALLOWED_ORIGINS[0];
  return ALLOWED_ORIGINS.includes(origin) ? origin : null;
}

function corsHeaders(origin: string | null): Record<string, string> {
  const allowed = allowedOrigin(origin);
  return allowed
    ? {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  }
    : { "Vary": "Origin" };
}

function json(payload: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...corsHeaders(origin),
    },
  });
}

interface Quote {
  id: string;
  user_id: string;
  customer_id: string | null;
  status: string;
  validity_date: string | null;
  viewed_at: string | null;
  share_token_expires_at: string | null;
  share_token_revoked_at: string | null;
  [key: string]: unknown;
}

function tokenFrom(url: string): string | null {
  const segments = new URL(url).pathname.split("/").filter(Boolean);
  const last = segments[segments.length - 1] ?? "";
  return TOKEN_PATTERN.test(last) ? last : null;
}

/// Expiry is computed rather than stored, so a quote that lapses while nobody
/// is looking still says so the moment it is opened.
function isExpired(quote: Quote): boolean {
  if (!quote.validity_date) return false;
  return quote.validity_date < new Date().toISOString().slice(0, 10);
}

function shareTokenActive(quote: Quote): boolean {
  if (quote.share_token_revoked_at) return false;
  if (!quote.share_token_expires_at) return true;
  return quote.share_token_expires_at > new Date().toISOString();
}

/// A quote already answered cannot be answered again from the link: reversing
/// a decision is a conversation, not a button.
function canDecide(quote: Quote): boolean {
  return !isExpired(quote) && (quote.status === "sent" || quote.status === "viewed");
}

async function loadQuote(token: string) {
  const { data: quote } = await admin
    .from("quotes")
    .select(
        "id, user_id, customer_id, title, number, status, currency, job_summary, " +
        "notes, scope, subtotal, tax_rate, tax_amount, total, validity_date, " +
        "created_at, viewed_at, decided_at, share_token_expires_at, share_token_revoked_at",
    )
    .eq("share_token", token)
    .maybeSingle();

  if (!quote) return null;

  const [items, business, customer] = await Promise.all([
    admin
      .from("quote_line_items")
      .select("description, type, quantity, unit, unit_price, position")
      .eq("quote_id", quote.id)
      .order("position", { ascending: true }),
    admin
      .from("business_profiles")
      .select(
        "business_name, phone, email, address, tax_number, default_terms, " +
          "default_notes, quote_number_prefix",
      )
      .eq("user_id", quote.user_id)
      .maybeSingle(),
    quote.customer_id
      ? admin.from("customers").select("name").eq("id", quote.customer_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  return {
    quote: quote as Quote,
    items: items.data ?? [],
    business: business.data ?? null,
    clientName: (customer.data as { name?: string } | null)?.name ?? null,
  };
}

/// What the page is given. Deliberately not the row: `user_id` and the internal
/// id are the owner's business, not the customer's, and nothing on the page
/// needs them.
function publicPayload(
  loaded: NonNullable<Awaited<ReturnType<typeof loadQuote>>>,
) {
  const { quote, items, business, clientName } = loaded;
  return {
    title: quote.title,
    number: quote.number,
    numberPrefix: (business as { quote_number_prefix?: string } | null)?.quote_number_prefix ?? "",
    status: quote.status,
    currency: quote.currency,
    jobSummary: quote.job_summary,
    notes: quote.notes,
    scope: quote.scope ?? [],
    subtotal: Number(quote.subtotal ?? 0),
    taxRate: Number(quote.tax_rate ?? 0),
    taxAmount: Number(quote.tax_amount ?? 0),
    total: Number(quote.total ?? 0),
    validityDate: quote.validity_date,
    createdAt: quote.created_at,
    decidedAt: quote.decided_at,
    expired: isExpired(quote),
    canDecide: canDecide(quote),
    clientName,
    items,
    business: business
      ? {
        name: (business as { business_name?: string }).business_name ?? null,
        phone: (business as { phone?: string }).phone ?? null,
        email: (business as { email?: string }).email ?? null,
        address: (business as { address?: string }).address ?? null,
        taxNumber: (business as { tax_number?: string }).tax_number ?? null,
        terms: (business as { default_terms?: string }).default_terms ?? null,
        footerNote: (business as { default_notes?: string }).default_notes ?? null,
      }
      : null,
  };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");

  if (req.method === "OPTIONS") {
    const status = allowedOrigin(origin) ? 204 : 403;
    return new Response(null, { status, headers: corsHeaders(origin) });
  }

  if (origin && !allowedOrigin(origin)) {
    return json({ error: "forbidden" }, 403, origin);
  }

  const token = tokenFrom(req.url);
  if (!token) return json({ error: "not_found" }, 404, origin);

  const loaded = await loadQuote(token);
  if (!loaded) return json({ error: "not_found" }, 404, origin);

  const { quote } = loaded;
  if (!shareTokenActive(quote)) {
    return json({ error: "not_found" }, 404, origin);
  }

  if (req.method === "POST") {
    const body = await req.json().catch(() => null);
    const action = String((body as { action?: string } | null)?.action ?? "");
    if (action !== "accept" && action !== "decline") {
      return json({ error: "bad_action" }, 400, origin);
    }
    // Re-checked here rather than trusting the page that sent it: the buttons
    // are absent when a quote can't be answered, but a POST can be made without
    // ever loading the page.
    if (!canDecide(quote)) {
      return json({ error: "already_answered", ...publicPayload(loaded) }, 409, origin);
    }
    const status = action === "accept" ? "accepted" : "declined";
    const decidedAt = new Date().toISOString();
    // Conditional on the status still being undecided, so the decision is made
    // by the database rather than by whichever of two near-simultaneous
    // requests happens to write last. `canDecide` above was read from a row
    // fetched a few queries ago; between then and here a second tap, a
    // double-submitting browser, or the owner marking it accepted in the app
    // can all have answered it already. Without the `in` filter both requests
    // pass the check and the second silently overwrites the first — a customer
    // who tapped Accept once can end up with a declined quote.
    const { data: decided } = await admin
      .from("quotes")
      .update({ status, decided_at: decidedAt, decided_by: "customer" })
      .eq("id", quote.id)
      .in("status", ["sent", "viewed"])
      .select("id");

    if (!decided || decided.length === 0) {
      // Somebody got there first. Re-read so the page shows what the quote
      // actually says now rather than what this request wanted it to say.
      const fresh = await loadQuote(token);
      return json(
        { error: "already_answered", ...publicPayload(fresh ?? loaded) },
        409,
        origin,
      );
    }

    quote.status = status;
    quote.decided_at = decidedAt;
    return json(publicPayload(loaded), 200, origin);
  }

  if (req.method !== "GET") {
    return json({ error: "method_not_allowed" }, 405, origin);
  }

  // Opening the link is the only thing that can ever set "viewed" — the app
  // shows that status prominently and, until this existed, nothing produced it.
  if (quote.status === "sent") {
    await admin
      .from("quotes")
      .update({
        status: "viewed",
        viewed_at: quote.viewed_at ?? new Date().toISOString(),
      })
      .eq("id", quote.id)
      // Only ever "sent" -> "viewed". Unconditional, this could walk an
      // accepted quote backwards if a decision landed between the read above
      // and this write.
      .eq("status", "sent");
    quote.status = "viewed";
  }

  return json(publicPayload(loaded), 200, origin);
});
