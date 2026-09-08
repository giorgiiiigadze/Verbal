// One deferred, high-accuracy transcription pass. The AssemblyAI credential is
// server-only: the iOS app uploads its temporary CAF here using its Supabase JWT.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.112.2";

const ASSEMBLYAI_API_KEY = Deno.env.get("ASSEMBLYAI_API_KEY");
const MAX_AUDIO_BYTES = 25 * 1024 * 1024;
const MAX_KEYTERMS = 1_000;
const admin = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
async function callerId(req: Request) {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data, error } = await admin.auth.getUser(token);
  return error ? null : data.user?.id ?? null;
}
function keyterms(req: Request): string[] {
  try {
    const raw = JSON.parse(req.headers.get("X-Verbal-Keyterms") ?? "[]");
    if (!Array.isArray(raw)) return [];
    return raw.slice(0, MAX_KEYTERMS).map(String).map(x => x.trim()).filter(x => x.length > 0 && x.length <= 50);
  } catch { return []; }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!ASSEMBLYAI_API_KEY) return json({ error: "Server not configured: missing ASSEMBLYAI_API_KEY" }, 500);
  const userId = await callerId(req);
  if (!userId) return json({ error: "Not signed in" }, 401);
  const declared = Number(req.headers.get("Content-Length") ?? "");
  if (Number.isFinite(declared) && declared > MAX_AUDIO_BYTES) return json({ error: "Recording is too long." }, 413);

  const audio = new Uint8Array(await req.arrayBuffer());
  if (audio.byteLength === 0 || audio.byteLength > MAX_AUDIO_BYTES) return json({ error: "Recording is too long." }, 413);

  // This is independently metered: transcribing is a paid external call even
  // if the later quote-extraction call fails.
  const { data: budget, error: budgetError } = await admin.rpc("reserve_request_budget", {
    p_user_id: userId, p_operation: "transcribe_audio",
  });
  if (budgetError || budget) return json({ error: "The accuracy pass is temporarily unavailable. Try again shortly." }, 429);

  const headers = { Authorization: ASSEMBLYAI_API_KEY };
  const upload = await fetch("https://api.assemblyai.com/v2/upload", { method: "POST", headers, body: audio });
  if (!upload.ok) return json({ error: "Could not upload recording for transcription." }, 502);
  const { upload_url } = await upload.json();
  const created = await fetch("https://api.assemblyai.com/v2/transcript", {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({
      audio_url: upload_url,
      // API identifiers use hyphens, not the display name's decimal point.
      // Universal-2 is the documented fallback for unsupported languages.
      speech_models: ["universal-3-5-pro", "universal-2"],
      keyterms_prompt: keyterms(req),
      format_text: true,
    }),
  });
  if (!created.ok) return json({ error: "Could not start the accuracy pass." }, 502);
  const { id } = await created.json();

  // Quotes are short. A bounded poll gives the app a final transcript in one
  // request; on a timeout it simply uses Apple's already-complete transcript.
  for (let attempt = 0; attempt < 30; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 1_000));
    const poll = await fetch(`https://api.assemblyai.com/v2/transcript/${id}`, { headers });
    if (!poll.ok) return json({ error: "The accuracy pass failed." }, 502);
    const result = await poll.json();
    if (result.status === "completed") {
      // Return provenance to the app. This is intentionally not inferred from
      // the requested model: AssemblyAI may select a configured fallback.
      return json({ transcript: result.text, model: result.speech_model_used ?? null });
    }
    if (result.status === "error") return json({ error: "The accuracy pass could not transcribe this recording." }, 422);
  }
  return json({ error: "The accuracy pass took too long." }, 504);
});
