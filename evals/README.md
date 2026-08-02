# Extraction evals

Answers one question: **did that change make the quotes better or worse?**

Without this, every prompt tweak and model swap is judged by generating one quote
and squinting at it. That is how the labour/material over-splitting bug on
2026-08-02 got shipped and then found by chance.

## Running it

```bash
OPENAI_API_KEY=sk-... node evals/run.mjs
```

No install step and no dependencies — Node 20+ only.

```bash
node evals/run.mjs --runs 5                  # more runs, tighter stability read
node evals/run.mjs --model gpt-5.6-terra     # compare models
node evals/run.mjs --fixture bathroom-retile # one case while iterating
```

Roughly $0.001 per run on luna, so a full pass is under a cent. It calls OpenAI
directly rather than the edge function, so it never touches the rate limit,
`usage_events`, or your production data.

The prompt and schema are imported from
`supabase/functions/extract-quote/prompt.mjs` — the same module the deployed
function uses. There is no second copy to drift out of sync.

## What it measures

| Metric | Meaning |
|---|---|
| **inventions** | A price on an item the speaker never priced. **Must be 0** — fails the run and exits non-zero. |
| **recall** | Did every job mentioned survive into the quote. |
| **extras** | Lines nobody asked for. Usually one job split into labour + material, which fills the quote with "Needs price" gaps that were never real. |
| **stability** | Same transcript, same shape across runs? GPT-5 rejects `temperature`, so sampling variance can't be tuned away — running each fixture several times is the only honest way to see it. |

Only invented prices fail the run. Everything else warns: a dropped item is
annoying, a fabricated price is a number the tradesperson might quote to a
customer and be held to.

## Adding fixtures — do this

The three shipped fixtures are **written, not recorded**. They cover the known
failure modes, but they are not how your users actually talk. The eval is worth
what its fixtures are worth, so replace them with real ones.

Take transcripts from the `transcripts` table (every generated quote saves one),
paste in the text, and hand-label what the quote *should* have contained:

```json
{
  "name": "short-kebab-name",
  "note": "Why this case exists — the failure it guards against.",
  "transcript": "What the tradesperson actually said, filler words and all.",
  "rate_card": [{ "name": "Socket fitted", "unit": "each", "unit_price": 60, "type": "labor" }],
  "currency": "USD",
  "expect": [
    {
      "label": "human-readable name for the report",
      "any": ["socket"],
      "exclude": ["spur"],
      "price": 60,
      "quantity": 10
    }
  ]
}
```

- `any` — the produced description must contain **at least one** of these substrings, lowercase.
- `exclude` — and **none** of these. This is how "re-tile" is kept apart from "remove old tiles".
- `price` — the spoken unit price, or `null` for "the speaker never priced this". `null` is what
  makes the invention check work, so mark unpriced items carefully.
- `quantity` — optional; include it for transcripts with corrections ("make that ten").
- `expect: []` — nothing quotable was said, so the model must return no line items.

Aim for 30–50 real transcripts. Prioritise the messy ones: heavy accents, mid-sentence
corrections, jobs where the price is deliberately left open, and rambling that trails off.
The clean ones already pass.
