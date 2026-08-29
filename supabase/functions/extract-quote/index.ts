// extract-quote — Step 2 of the AI pipeline (server-side).
//
// Input : { transcript, rate_card?, business_defaults?, trade_context? }
// Output: strict JSON quote (see the product spec §7).
//
// The OpenAI key is read from the OPENAI_API_KEY secret and never leaves the
// server. Prices are never invented; totals/tax are computed in the app, not here.
//
// Every call is rate-limited per user and logged to usage_events with the token
// counts OpenAI actually charged for. Without the limit a single account could
// run the OpenAI bill up without bound; without the log, per-user cost is a
// guess.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.112.2";
// Prompt + schema live in prompt.mjs so the eval harness scores what ships.
// Both files must be deployed together.
import { QUOTE_SCHEMA, SYSTEM_PROMPT, buildUserPrompt } from "./prompt.mjs";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const MODEL = "gpt-5.6-luna";

/// USD per million tokens. Keep in step with MODEL — this is what turns the
/// usage log into real money rather than raw counts.
const PRICING: Record<string, { input: number; cached: number; output: number }> = {
  "gpt-5.6-luna": { input: 0.20, cached: 0.02, output: 1.20 },
  "gpt-5.6-terra": { input: 2.00, cached: 0.20, output: 12.00 },
  "gpt-5-mini": { input: 0.25, cached: 0.025, output: 2.00 },
  "gpt-4o-mini": { input: 0.15, cached: 0.075, output: 0.60 },
};

/// Generous enough that no real tradesperson will meet them — a busy one writes
/// a handful of quotes a day — but low enough to cap a runaway script.
const HOURLY_LIMIT = 30;
const DAILY_LIMIT = 150;

/// The call limits above cap how often, not how much, and the bill is charged
/// per token. Thirty calls an hour carrying a megabyte of "transcript" each is
/// a runaway bill that never trips a rate limit — the limiter was counting the
/// wrong unit on its own.
///
/// 24k characters is roughly forty minutes of continuous speech. No dictated
/// job description comes close; anything that does is not a job description.
const MAX_TRANSCRIPT_CHARS = 24_000;
/// A rate card is the user's own price list. A few hundred entries is a large
/// established business; past that it is someone testing what fits.
const MAX_RATE_CARD_ITEMS = 400;
const MAX_RATE_CARD_NAME_CHARS = 200;
/// Bounds the other half of the bill. The schema-constrained answer for a real
/// job is a small fraction of this; the cap is only here so a model that starts
/// repeating itself stops costing money at some point.
const MAX_OUTPUT_TOKENS = 4_000;
/// Everything else in the body — trade, currency, business defaults — is short
/// by nature, so one ceiling over the whole payload covers them together.
const MAX_BODY_BYTES = 128 * 1024;

/// Refuse on the declared length before reading, so an oversized body is turned
/// away at the header rather than buffered in full and then rejected. A missing
/// or lying Content-Length just means the check below does the work instead.
function declaredTooLarge(req: Request): boolean {
  const declared = Number(req.headers.get("Content-Length") ?? "");
  return Number.isFinite(declared) && declared > MAX_BODY_BYTES;
}

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false, autoRefreshToken: false } },
);

interface RateCardItem {
  name: string;
  unit?: string | null;
  unit_price?: number | null;
  type?: "labor" | "material" | "other";
}

interface RequestBody {
  transcript?: string;
  rate_card?: RateCardItem[];
  business_defaults?: Record<string, unknown>;
  trade_context?: string;
  /// ISO 4217 code of the user's main currency (e.g. "GBP"), for any money
  /// referenced in prose like job_summary. Prices themselves stay numeric.
  currency?: string;
}

/// The caller's user id, taken from the JWT the client sends. verify_jwt already
/// guarantees the token is valid; this reads who it belongs to.
async function callerId(req: Request): Promise<string | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user.id;
}

/// Returns the window that has been exhausted ("hour"/"day"), "meter" when the
/// limiter cannot verify usage, or null to proceed.
async function exhaustedWindow(userId: string): Promise<string | null> {
  const now = Date.now();
  const windows: Array<[string, number, string]> = [
    [new Date(now - 3_600_000).toISOString(), HOURLY_LIMIT, "hour"],
    [new Date(now - 86_400_000).toISOString(), DAILY_LIMIT, "day"],
  ];
  for (const [since, limit, label] of windows) {
    const { count, error } = await admin
      .from("usage_events")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .neq("outcome", "rate_limited")
      .gte("created_at", since);
    if (error) {
      console.error("rate-limit check failed, refusing:", error.message);
      return "meter";
    }
    if ((count ?? 0) >= limit) return label;
  }
  return null;
}

interface UsageRow {
  user_id: string;
  model: string;
  tokens_in?: number;
  tokens_cached?: number;
  tokens_out?: number;
  tokens_reasoning?: number;
  cost_usd?: number;
  duration_ms?: number;
  outcome: "ok" | "rate_limited" | "model_error";
}

async function logUsage(row: UsageRow): Promise<void> {
  const { error } = await admin.from("usage_events").insert(row);
  // Never fail the user's quote because the meter did not write.
  if (error) console.error("usage log failed:", error.message);
}

function priceOf(tokensIn: number, cached: number, tokensOut: number): number {
  const rate = PRICING[MODEL];
  if (!rate) return 0;
  const uncached = Math.max(tokensIn - cached, 0);
  return (uncached * rate.input + cached * rate.cached + tokensOut * rate.output) / 1_000_000;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!OPENAI_API_KEY) {
    return json({ error: "Server not configured: missing OPENAI_API_KEY" }, 500);
  }

  const userId = await callerId(req);
  if (!userId) {
    return json({ error: "Not signed in" }, 401);
  }

  if (declaredTooLarge(req)) {
    return json({ error: "That recording is too long to turn into a quote." }, 413);
  }

  // Read as text rather than `req.json()` so the size is known before anything
  // is parsed, and checked again here because Content-Length is the sender's
  // claim about the body, not a fact about it.
  const raw = await req.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
    return json({ error: "That recording is too long to turn into a quote." }, 413);
  }

  let body: RequestBody;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!body.transcript || body.transcript.trim().length === 0) {
    return json({ error: "transcript is required" }, 400);
  }
  if (body.transcript.length > MAX_TRANSCRIPT_CHARS) {
    return json({ error: "That recording is too long to turn into a quote." }, 413);
  }

  // Trimmed rather than refused: an oversized rate card is the user's own price
  // list having grown, not an attack, and quietly using the first few hundred
  // entries produces a quote where refusing produces a dead end. The prompt
  // only ever needed the prices likely to be spoken about.
  if (Array.isArray(body.rate_card)) {
    body.rate_card = body.rate_card
      .slice(0, MAX_RATE_CARD_ITEMS)
      .map((item) => ({
        ...item,
        name: String(item?.name ?? "").slice(0, MAX_RATE_CARD_NAME_CHARS),
      }));
  } else {
    body.rate_card = undefined;
  }

  const window = await exhaustedWindow(userId);
  if (window) {
    await logUsage({ user_id: userId, model: MODEL, outcome: "rate_limited" });
    if (window === "meter") {
      return json({
        error: "Quote extraction is temporarily unavailable. Try again shortly.",
      }, 503);
    }
    return json({
      error: window === "hour"
        ? "That's a lot of quotes in one hour. Try again shortly."
        : "You've hit today's limit on new quotes. Try again tomorrow.",
    }, 429);
  }

  const startedAt = Date.now();
  try {
    const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: buildUserPrompt(body) },
        ],
        response_format: { type: "json_schema", json_schema: QUOTE_SCHEMA },
        max_completion_tokens: MAX_OUTPUT_TOKENS,
      }),
    });

    if (!openaiRes.ok) {
      const detail = await openaiRes.text();
      console.error("OpenAI request failed:", openaiRes.status, detail);
      await logUsage({
        user_id: userId,
        model: MODEL,
        duration_ms: Date.now() - startedAt,
        outcome: "model_error",
      });
      return json({ error: "Quote extraction failed. Try again shortly." }, 502);
    }

    const data = await openaiRes.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      await logUsage({
        user_id: userId,
        model: MODEL,
        duration_ms: Date.now() - startedAt,
        outcome: "model_error",
      });
      return json({ error: "Empty response from model" }, 502);
    }

    // Parse before the meter writes. Doing it after would log an "ok" row and
    // then a "model_error" row from the catch below for one call — two slots of
    // the caller's rate limit, and one billed extraction counted twice.
    const quote = JSON.parse(content);

    const usage = data.usage ?? {};
    const tokensIn: number = usage.prompt_tokens ?? 0;
    const tokensOut: number = usage.completion_tokens ?? 0;
    const cached: number = usage.prompt_tokens_details?.cached_tokens ?? 0;
    const reasoning: number = usage.completion_tokens_details?.reasoning_tokens ?? 0;

    await logUsage({
      user_id: userId,
      model: MODEL,
      tokens_in: tokensIn,
      tokens_cached: cached,
      tokens_out: tokensOut,
      tokens_reasoning: reasoning,
      cost_usd: priceOf(tokensIn, cached, tokensOut),
      duration_ms: Date.now() - startedAt,
      outcome: "ok",
    });

    return json({ quote });
  } catch (err) {
    console.error("Extraction failed:", err);
    await logUsage({
      user_id: userId,
      model: MODEL,
      duration_ms: Date.now() - startedAt,
      outcome: "model_error",
    });
    return json({ error: "Quote extraction failed. Try again shortly." }, 500);
  }
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
