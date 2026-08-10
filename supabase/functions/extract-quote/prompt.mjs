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
- "job_summary" is one or two sentences of context: who the work is for, where it is, and any terms the speaker states — deposits, timing, how long the price holds, access arrangements. It must NOT re-list the tasks. "scope" sits directly beneath it on screen and names them already, so a summary that lists them again makes a short quote read as padding. If the speaker gave no context or terms, one plain sentence naming the job is enough. It must NOT state what anything costs: a price belongs in the table, once, where the user can edit it — say it here too and the two disagree the moment they change one. A deposit or a discount stated as a share ("30% to hold the date") is the term itself and belongs here; the amount charged for a piece of work does not. Every clause must say something a reader did not already know: drop any that restates the obvious ("includes the terms stated in the package") rather than padding the sentence out with it. "title" is the compact label.
- "scope" is a short bulleted list of what the job covers — 3 to 6 concise phrases, each a distinct stage or deliverable of the work (e.g. "Remove existing tiles and dispose of waste", "Fit new toilet and connect to soil pipe"). Keep each under about ten words, written for the customer to read. It must NOT contain prices, quantities, or amounts — it describes the work, not the money. INCLUDE work the speaker says is covered by another line ("venue liaison is included in the package"): it carries no separate charge but the customer is still paying for it, and scope is the part they read. Leave out only what the speaker says they are NOT doing. This applies to "scope" ALONE — such work must NEVER become a line item, at zero or at any other price.
- "customer" is who the quote is for. When the speaker names the person or business the work is for ("this one's for Marina", "quote for Mrs Chen at number 42"), put that name in customer.name, and any address they give in customer.address. If they never say who it is for, leave both null — NEVER take a name from the job description or invent one, for the same reason prices are never invented.
- Include EVERY distinct task, job, or material the speaker mentions as its own line item — EVEN IF it has no price. NEVER omit an item just because its price is unknown; instead include it with the stated quantity/unit (or null) and price_source "missing". The ONLY things you may leave out are items the speaker explicitly says to fold into another line (e.g. "grouting is included in the tiling price") or explicitly says to exclude (e.g. "materials he's buying himself").
- Do NOT split one spoken job into separate labor and material lines. "Replace the toilet for ninety" is ONE line item — not an installation line plus a toilet line. Only separate them when the speaker separates them: by pricing them apart, or by naming the thing to buy and the work to do as distinct items. Splitting one job in two manufactures a "missing" price the speaker never left, and turns a finished quote into one that looks full of holes.
- BUT when a price is attached by a pronoun to only PART of what was just named, it prices only that part, and the rest becomes its own line with price_source "missing". "Day-of coordination with two assistants, they're 200 each" prices the ASSISTANTS — "they" cannot refer to the coordination — so it is two lines: the assistants at 2 × 200, and the coordination itself unpriced and flagged. Read "they", "those", "each of them" as pointing at the nearest plural thing named, not at the whole arrangement. Folding both into one line at 400 is the most expensive mistake available here: it reads as a confident, complete line while quietly giving away the fee the speaker never priced, and nothing on the quote would show it was missing.
- One price the speaker could not give is ONE line, however many things it covers. "Centerpieces on twelve tables plus the arch — I can't price that yet" is a single unpriced line: "that" is one job and one call to the florist, so splitting it into a centerpieces line and an arch line manufactures two gaps where the speaker left one.
- NEVER invent prices. If an item has no spoken price and no rate-card match, set unit_price to null and price_source to "missing".
- NEVER write 0 as a price. Zero is a claim that the work is free, and "included in the package" is not that claim — it means the charge lives on another line. Work described that way belongs in "scope" and nowhere else; it must not appear in line_items at all. price_source "spoken" requires a number the speaker actually said out loud.
- If the speaker states a price, use it and set price_source to "spoken".
- A price given for the work as a whole is the TOTAL for that line, not a rate. "Day and a half of work, call it 400 for the labour" is quantity 1, unit_price 400 — NOT 1.5 days at 400 a day. NEVER multiply a stated lump sum by a duration or count mentioned near it; that invents money the speaker never said, and it does it in a line that looks confident rather than flagged. Only treat a price as a rate when the speaker says so ("400 a day", "45 per metre", "90 each").
- If an item (without a spoken price) matches an item in the provided rate card by name/meaning, use that unit_price and set price_source to "rate_card".
- Preserve the user's own wording in descriptions where reasonable — tradespeople trust their own phrasing.
- Classify each line item as "labor", "material", or "other".
- Handle filler words and mid-speech corrections ("actually make that eight outlets") — use the corrected value.
- Set confidence to "low" for any quantity or price you are unsure about, "high" otherwise.
- Add a short string to "flags" for anything that needs the user's attention: a missing price, an ambiguous quantity, a scope you could not resolve, two readings you had to choose between. Terms the speaker stated plainly — deposits, validity, payment schedules — are NOT flags. There is nothing to check about them and they are already in job_summary; repeating them there and here puts the same sentence on screen twice. If nothing needs attention, return an empty array.
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
