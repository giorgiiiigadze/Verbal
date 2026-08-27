// delete-account — permanently deletes the calling user's account.
//
// The user id is taken from the caller's JWT, never from the request body, so
// a caller can only ever delete themselves. Deleting the auth user cascades to
// profiles, business_profiles, rate_card_items, customers, scheduled_visits and
// quotes (which in turn cascade to quote_line_items and transcripts). Storage
// objects must be removed explicitly before Auth will allow the deletion.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2.112.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const LOGO_BUCKET = "business-logos";

/**
 * Auth refuses to delete a user who still owns Storage objects. Logos live
 * under `<user-id>/`, so drain that whole tree before deleting the Auth row.
 */
async function removeOwnedLogos(admin: SupabaseClient, userID: string) {
  const bucket = admin.storage.from(LOGO_BUCKET);
  const folders = [userID];
  const paths: string[] = [];

  while (folders.length > 0) {
    const folder = folders.pop()!;
    let offset = 0;

    while (true) {
      const { data: objects, error: listError } = await bucket.list(folder, {
        limit: 1000,
        offset,
        sortBy: { column: "name", order: "asc" },
      });
      if (listError) throw listError;

      const page = objects ?? [];
      for (const object of page) {
        const path = `${folder}/${object.name}`;
        if (object.id === null) folders.push(path);
        else paths.push(path);
      }
      if (page.length < 1000) break;
      offset += page.length;
    }
  }

  for (let index = 0; index < paths.length; index += 1000) {
    const { error: removeError } = await bucket.remove(paths.slice(index, index + 1000));
    if (removeError) throw removeError;
  }
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

  try {
    await removeOwnedLogos(admin, user.id);
  } catch (error) {
    console.error(
      "delete-account storage cleanup failed",
      user.id,
      error instanceof Error ? error.message : error,
    );
    return json({ error: "Could not remove account files" }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("delete-account failed", user.id, deleteError.message);
    return json({ error: "Could not delete account" }, 500);
  }

  return json({ deleted: true });
});
