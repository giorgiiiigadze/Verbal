// The extraction prompt and output schema, kept in their own module so the eval
// harness scores the same text production uses. A second copy would drift, and a
// drifting eval is worse than no eval — it reports on a prompt nobody runs.
//
// Plain .mjs so both runtimes can load it unambiguously: Deno for the edge
// function, Node for evals/run.mjs.

// Strict schema matching spec §7 — used with OpenAI Structured Outputs.
export const QUOTE_SCHEMA = {
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
};

export const SYSTEM_PROMPT = `You convert a tradesperson's spoken job description into a structured, itemized quote.

Rules:
- "title" is a short, concrete name for the job itself — a 3 to 6 word noun phrase describing the work (e.g. "Bathroom re-tiling & toilet swap", "Kitchen socket installation"). It must NOT be conversational, a greeting, or a full sentence, and must NOT start with words like "Thanks", "Here's", or "Sure".
- "job_summary" may be a friendly sentence or two describing the quote; "title" is the compact label.
- "scope" is a short bulleted list of what the job covers — 3 to 6 concise phrases, each a distinct stage or deliverable of the work (e.g. "Remove existing tiles and dispose of waste", "Fit new toilet and connect to soil pipe"). Keep each under about ten words, written for the customer to read. It must NOT contain prices, quantities, or amounts — it describes the work, not the money.
- "customer" is who the quote is for. When the speaker names the person or business the work is for ("this one's for Marina", "quote for Mrs Chen at number 42"), put that name in customer.name, and any address they give in customer.address. If they never say who it is for, leave both null — NEVER take a name from the job description or invent one, for the same reason prices are never invented.
- Include EVERY distinct task, job, or material the speaker mentions as its own line item — EVEN IF it has no price. NEVER omit an item just because its price is unknown; instead include it with the stated quantity/unit (or null) and price_source "missing". The ONLY things you may leave out are items the speaker explicitly says to fold into another line (e.g. "grouting is included in the tiling price") or explicitly says to exclude (e.g. "materials he's buying himself").
- Do NOT split one spoken job into separate labor and material lines. "Replace the toilet for ninety" is ONE line item — not an installation line plus a toilet line. Only separate them when the speaker separates them: by pricing them apart, or by naming the thing to buy and the work to do as distinct items. Splitting one job in two manufactures a "missing" price the speaker never left, and turns a finished quote into one that looks full of holes.
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

/// Builds the user-side message. Shared so the eval feeds the model exactly what
/// production does, rate card included.
export function buildUserPrompt(body) {
  const parts = [];
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
