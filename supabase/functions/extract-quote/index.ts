// extract-quote — Step 2 of the AI pipeline (server-side).
//
// Input : { transcript, rate_card?, business_defaults?, trade_context? }
// Output: strict JSON quote (see the product spec §7).
//
// The OpenAI key is read from the OPENAI_API_KEY secret and never leaves the
// server. Prices are never invented; totals/tax are computed in the app, not here.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const MODEL = "gpt-5.6-luna";

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

// Strict schema matching spec §7 — used with OpenAI Structured Outputs.
const QUOTE_SCHEMA = {
  name: "quote_extraction",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      title: { type: "string" },
      job_summary: { type: "string" },
      scope: { type: "array", items: { type: "string" } },
      customer: {
        type: "object",
        additionalProperties: false,
        properties: {
          name: { type: ["string", "null"] },
          address: { type: ["string", "null"] },
        },
        required: ["name", "address"],
      },
      line_items: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            description: { type: "string" },
            type: { type: "string", enum: ["labor", "material", "other"] },
            quantity: { type: ["number", "null"] },
            unit: { type: ["string", "null"] },
            unit_price: { type: ["number", "null"] },
            price_source: { type: "string", enum: ["spoken", "rate_card", "missing"] },
            confidence: { type: "string", enum: ["high", "low"] },
          },
          required: [
            "description",
            "type",
            "quantity",
            "unit",
            "unit_price",
            "price_source",
            "confidence",
          ],
        },
      },
      notes: { type: ["string", "null"] },
      flags: { type: "array", items: { type: "string" } },
    },
    required: ["title", "job_summary", "scope", "customer", "line_items", "notes", "flags"],
  },
} as const;

const SYSTEM_PROMPT = `You convert a tradesperson's spoken job description into a structured, itemized quote.

Rules:
- "title" is a short, concrete name for the job itself — a 3 to 6 word noun phrase describing the work (e.g. "Bathroom re-tiling & toilet swap", "Kitchen socket installation"). It must NOT be conversational, a greeting, or a full sentence, and must NOT start with words like "Thanks", "Here's", or "Sure".
- "job_summary" may be a friendly sentence or two describing the quote; "title" is the compact label.
- "scope" is a short bulleted list of what the job covers — 3 to 6 concise phrases, each a distinct stage or deliverable of the work (e.g. "Remove existing tiles and dispose of waste", "Fit new toilet and connect to soil pipe"). Keep each under about ten words, written for the customer to read. It must NOT contain prices, quantities, or amounts — it describes the work, not the money.
- Include EVERY distinct task, job, or material the speaker mentions as its own line item — EVEN IF it has no price. NEVER omit an item just because its price is unknown; instead include it with the stated quantity/unit (or null) and price_source "missing". The ONLY things you may leave out are items the speaker explicitly says to fold into another line (e.g. "grouting is included in the tiling price") or explicitly says to exclude (e.g. "materials he's buying himself").
- NEVER invent prices. If an item has no spoken price and no rate-card match, set unit_price to null and price_source to "missing".
- If the speaker states a price, use it and set price_source to "spoken".
- If an item (without a spoken price) matches an item in the provided rate card by name/meaning, use that unit_price and set price_source to "rate_card".
- Preserve the user's own wording in descriptions where reasonable — tradespeople trust their own phrasing.
- Classify each line item as "labor", "material", or "other".
- Handle filler words and mid-speech corrections ("actually make that eight outlets") — use the corrected value.
- Set confidence to "low" for any quantity or price you are unsure about, "high" otherwise.
- Add a short string to "flags" for anything that needs the user's attention (missing prices, ambiguous quantities, unclear scope).
- Do NOT compute totals or tax — that is done by the app.
- If the transcript does NOT describe a quotable job (e.g. a greeting, small talk, silence, or too little detail to build a quote), return line_items as an EMPTY array and set job_summary to a short, friendly note (one or two sentences) telling the user there wasn't enough to build a quote and inviting them to describe the job — the tasks, quantities, and prices — then try again.
Return only data that conforms to the provided schema.`;

function buildUserPrompt(body: RequestBody): string {
  const parts: string[] = [];
  if (body.trade_context) {
    parts.push(`Trade context: ${body.trade_context}`);
  }
  if (body.rate_card && body.rate_card.length > 0) {
    parts.push(`Rate card (saved prices):\n${JSON.stringify(body.rate_card)}`);
  } else {
    parts.push("Rate card: (none saved)");
  }
  if (body.business_defaults) {
    parts.push(`Business defaults: ${JSON.stringify(body.business_defaults)}`);
  }
  if (body.currency) {
    parts.push(`Currency: ${body.currency}. If you mention any amount in job_summary or flags, use this currency's symbol. Line-item unit_price values must stay plain numbers with no symbol.`);
  }
  parts.push(`Transcript:\n"""${body.transcript ?? ""}"""`);
  return parts.join("\n\n");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!OPENAI_API_KEY) {
    return json({ error: "Server not configured: missing OPENAI_API_KEY" }, 500);
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!body.transcript || body.transcript.trim().length === 0) {
    return json({ error: "transcript is required" }, 400);
  }

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
      }),
    });

    if (!openaiRes.ok) {
      const detail = await openaiRes.text();
      return json({ error: "OpenAI request failed", detail }, 502);
    }

    const data = await openaiRes.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      return json({ error: "Empty response from model" }, 502);
    }

    const quote = JSON.parse(content);
    return json({ quote });
  } catch (err) {
    return json({ error: "Extraction failed", detail: String(err) }, 500);
  }
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
