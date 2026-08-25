// delete-account — permanently deletes the calling user's account.
//
// The user id is taken from the caller's JWT, never from the request body, so
// a caller can only ever delete themselves. Deleting the auth user cascades to
// profiles, business_profiles, rate_card_items, customers, scheduled_visits and
// quotes (which in turn cascade to quote_line_items and transcripts), so no
// manual cleanup is needed here.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  // Resolve the caller from their own token.
  const caller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) {
    return json({ error: "Invalid session" }, 401);
  }

  // Service role is required to remove an auth user; the id still comes from
  // the verified token above.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("delete-account failed", user.id, deleteError.message);
    return json({ error: "Could not delete account" }, 500);
  }

  return json({ deleted: true });
});
