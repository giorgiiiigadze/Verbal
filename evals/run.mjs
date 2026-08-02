#!/usr/bin/env node
//
// Extraction eval. Runs each fixture through the real prompt several times and
// scores what comes back, so "is the model better?" stops being a feeling.
//
//   OPENAI_API_KEY=sk-... node evals/run.mjs
//   OPENAI_API_KEY=sk-... node evals/run.mjs --runs 5 --model gpt-5.6-terra
//   OPENAI_API_KEY=sk-... node evals/run.mjs --fixture bathroom-retile
//
// It imports SYSTEM_PROMPT and QUOTE_SCHEMA straight from the edge function's
// prompt.mjs, so it can only ever score the prompt that actually ships.
//
// Four things are measured. They are not equally important:
//
//   inventions  a price on an item the speaker never priced. Must be 0. This is
//               the only failure that can cost the user money in front of a
//               customer, so it fails the run on its own.
//   recall      did every job mentioned survive into the quote.
//   extras      lines the speaker never asked for — usually one job split into a
//               labour line plus a material line, which litters the quote with
//               "Needs price" gaps that were never real.
//   stability   same transcript, same prompt, same shape? Sampling variance is
//               real and cannot be tuned away with temperature on GPT-5, so the
//               only honest way to see it is to run each fixture more than once.

import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { QUOTE_SCHEMA, SYSTEM_PROMPT, buildUserPrompt }
  from "../supabase/functions/extract-quote/prompt.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, "fixtures");

// Per million tokens — mirrors PRICING in the edge function.
const PRICING = {
  "gpt-5.6-luna": { input: 0.20, output: 1.20 },
  "gpt-5.6-terra": { input: 2.00, output: 12.00 },
  "gpt-5-mini": { input: 0.25, output: 2.00 },
  "gpt-4o-mini": { input: 0.15, output: 0.60 },
};

function parseArgs(argv) {
  const args = { runs: 3, model: "gpt-5.6-luna", fixture: null };
  for (let i = 0; i < argv.length; i += 1) {
    const [flag, inline] = argv[i].split("=");
    const value = inline ?? argv[i + 1];
    if (flag === "--runs") args.runs = Number(value);
    else if (flag === "--model") args.model = value;
    else if (flag === "--fixture") args.fixture = value;
    else continue;
    if (inline === undefined) i += 1;
  }
  return args;
}

async function loadFixtures(only) {
  const names = (await readdir(FIXTURES)).filter((f) => f.endsWith(".json"));
  const loaded = [];
  for (const file of names) {
    const fixture = JSON.parse(await readFile(join(FIXTURES, file), "utf8"));
    if (!only || fixture.name === only) loaded.push(fixture);
  }
  if (loaded.length === 0) throw new Error(`No fixture matched "${only}"`);
  return loaded.sort((a, b) => a.name.localeCompare(b.name));
}

async function extract(fixture, model, apiKey) {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: buildUserPrompt(fixture) },
      ],
      response_format: { type: "json_schema", json_schema: QUOTE_SCHEMA },
    }),
  });
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return {
    quote: JSON.parse(data.choices[0].message.content),
    usage: data.usage ?? {},
  };
}

/// An expected item matches a produced line when any of its keywords appears and
/// none of its exclusions do. Deliberately explicit rather than fuzzy: a scorer
/// that guesses is a scorer you end up debugging instead of the prompt.
export function matches(expected, description) {
  const text = description.toLowerCase();
  if (expected.exclude?.some((word) => text.includes(word))) return false;
  return expected.any.some((word) => text.includes(word));
}

export function score(fixture, quote) {
  const produced = quote.line_items ?? [];
  const taken = new Set();
  const missing = [];
  const priceErrors = [];
  const inventions = [];
  let matched = 0;

  for (const expected of fixture.expect) {
    const index = produced.findIndex(
      (item, i) => !taken.has(i) && matches(expected, item.description ?? ""),
    );
    if (index === -1) {
      missing.push(expected.label);
      continue;
    }
    taken.add(index);
    matched += 1;
    const item = produced[index];

    if (expected.price === null) {
      // The speaker never gave a price. A number here is fabricated money.
      if (item.unit_price !== null && item.unit_price !== undefined) {
        inventions.push(`${expected.label} → ${item.unit_price}`);
      }
    } else if (Number(item.unit_price) !== Number(expected.price)) {
      priceErrors.push(`${expected.label}: want ${expected.price}, got ${item.unit_price}`);
    }
    if (expected.quantity !== undefined && Number(item.quantity) !== Number(expected.quantity)) {
      priceErrors.push(`${expected.label}: qty want ${expected.quantity}, got ${item.quantity}`);
    }
  }

  const extras = produced
    .filter((_, i) => !taken.has(i))
    .map((item) => item.description);

  return {
    matched,
    expected: fixture.expect.length,
    missing,
    extras,
    priceErrors,
    inventions,
    // Shape fingerprint, for the stability check across repeated runs.
    shape: `${matched}/${fixture.expect.length}+${extras.length}`,
  };
}

function costOf(usage, model) {
  const rate = PRICING[model];
  if (!rate) return 0;
  return ((usage.prompt_tokens ?? 0) * rate.input
    + (usage.completion_tokens ?? 0) * rate.output) / 1e6;
}

const RED = "\x1b[31m", GREEN = "\x1b[32m", YELLOW = "\x1b[33m", DIM = "\x1b[2m", OFF = "\x1b[0m";

async function main() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    console.error("Set OPENAI_API_KEY (the same key the edge function uses).");
    process.exit(2);
  }
  const { runs, model, fixture: only } = parseArgs(process.argv.slice(2));
  const fixtures = await loadFixtures(only);

  console.log(`\nmodel ${model} · ${runs} run(s) per fixture · ${fixtures.length} fixture(s)\n`);

  let totalCost = 0;
  let anyFailure = false;
  const summary = [];

  for (const fixture of fixtures) {
    const results = [];
    for (let run = 0; run < runs; run += 1) {
      let outcome;
      try {
        outcome = await extract(fixture, model, apiKey);
      } catch (err) {
        console.log(`${RED}✗${OFF} ${fixture.name} run ${run + 1}: ${err.message}`);
        anyFailure = true;
        continue;
      }
      totalCost += costOf(outcome.usage, model);
      results.push(score(fixture, outcome.quote));
    }
    if (results.length === 0) continue;

    const recall = results.reduce((sum, r) => sum + (r.expected ? r.matched / r.expected : 1), 0)
      / results.length;
    const inventions = results.reduce((sum, r) => sum + r.inventions.length, 0);
    const extras = results.reduce((sum, r) => sum + r.extras.length, 0) / results.length;
    const priceErrors = results.reduce((sum, r) => sum + r.priceErrors.length, 0);
    const shapes = new Set(results.map((r) => r.shape));
    const stable = shapes.size === 1;

    const failed = inventions > 0 || priceErrors > 0 || recall < 1;
    if (failed) anyFailure = true;

    const mark = inventions > 0 ? `${RED}✗${OFF}`
      : failed ? `${YELLOW}!${OFF}`
      : stable ? `${GREEN}✓${OFF}` : `${YELLOW}~${OFF}`;

    console.log(`${mark} ${fixture.name}`);
    console.log(`    recall ${(recall * 100).toFixed(0)}%  ·  extras ${extras.toFixed(1)}/run  ·  `
      + `price errors ${priceErrors}  ·  inventions ${inventions}  ·  `
      + `${stable ? "stable" : `${YELLOW}unstable${OFF} (${[...shapes].join(", ")})`}`);

    const missing = [...new Set(results.flatMap((r) => r.missing))];
    const extraList = [...new Set(results.flatMap((r) => r.extras))];
    const invented = [...new Set(results.flatMap((r) => r.inventions))];
    const wrongPrices = [...new Set(results.flatMap((r) => r.priceErrors))];
    if (missing.length) console.log(`    ${DIM}dropped:${OFF} ${missing.join(" · ")}`);
    if (extraList.length) console.log(`    ${DIM}extra lines:${OFF} ${extraList.join(" · ")}`);
    if (wrongPrices.length) console.log(`    ${DIM}wrong:${OFF} ${wrongPrices.join(" · ")}`);
    if (invented.length) console.log(`    ${RED}INVENTED PRICES:${OFF} ${invented.join(" · ")}`);
    console.log();

    summary.push({ name: fixture.name, recall, extras, inventions, priceErrors, stable });
  }

  const meanRecall = summary.reduce((s, r) => s + r.recall, 0) / (summary.length || 1);
  const allInventions = summary.reduce((s, r) => s + r.inventions, 0);
  const unstable = summary.filter((r) => !r.stable).map((r) => r.name);

  console.log(`${DIM}────${OFF}`);
  console.log(`recall ${(meanRecall * 100).toFixed(0)}%  ·  inventions ${allInventions}  ·  `
    + `unstable ${unstable.length ? unstable.join(", ") : "none"}  ·  `
    + `cost $${totalCost.toFixed(4)}`);
  console.log(allInventions > 0
    ? `\n${RED}FAIL${OFF} — the model priced something the speaker never priced.`
    : anyFailure
      ? `\n${YELLOW}WARN${OFF} — no invented prices, but items were dropped, mispriced or unstable.`
      : `\n${GREEN}PASS${OFF}`);

  process.exit(allInventions > 0 ? 1 : 0);
}

// Only run when invoked directly, so the scorer can be imported and tested
// without spending money on OpenAI calls.
if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err);
    process.exit(2);
  });
}
