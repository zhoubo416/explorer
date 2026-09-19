import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

/**
 * 删除当前登录用户的账号。
 *
 * 只删 auth.users 一行：explore_ 前缀的表（画像、会话、消息、目标、记忆、事件、
 * 观察、行动、记忆关系、周报、每日建议）的 user_id 全部是
 * `references auth.users(id) on delete cascade`，级联即清空业务数据，
 * 因此这里不逐表删除，避免新增表时漏删。
 *
 * 删除 auth 用户必须用 service role（GoTrue 管理接口），所以先用调用者自己的
 * JWT 确认身份、只允许删自己，再用 service role 执行。
 */
Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseAnonKey) {
      return jsonResponse({ error: "Service is not configured" }, 503);
    }
    if (!serviceRoleKey) return jsonResponse({ error: "Service role not configured" }, 503);

    const authHeader = request.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing authorization" }, 401);
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return jsonResponse({ error: "Unauthorized" }, 401);
    const userId = userData.user.id;

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) return jsonResponse({ error: deleteError.message }, 500);

    return jsonResponse({ deleted: true });
  } catch (err) {
    return jsonResponse({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
