// Shared helpers for GoLesson Edge Functions (docs/05 section 2).
// Caller must be a logged-in teacher with an active profile; data access after
// that check uses the service_role client (parse_logs/reports writes are
// service-side by design -- clients only get the narrow RLS paths in 04 section 5).

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export function errorResponse(status: number, code: string, message: string): Response {
  return jsonResponse(status, { error: code, message });
}

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export function handleOptions(req: Request): Response | null {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return null;
}

// Verifies the caller JWT and the active-teacher profile.
// Returns the caller uuid, or a ready-to-return error Response.
export async function requireActiveTeacher(
  req: Request,
  svc: SupabaseClient,
): Promise<{ userId: string } | Response> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return errorResponse(401, "unauthorized", "로그인이 필요합니다.");

  const { data, error } = await svc.auth.getUser(jwt);
  if (error || !data?.user) {
    return errorResponse(401, "unauthorized", "로그인이 필요합니다.");
  }

  const { data: profile } = await svc
    .from("profiles")
    .select("id, active")
    .eq("id", data.user.id)
    .maybeSingle();
  if (!profile?.active) {
    return errorResponse(403, "forbidden", "비활성 계정입니다. 관리자에게 문의하세요.");
  }
  return { userId: data.user.id };
}
