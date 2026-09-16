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

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    const apiKey = Deno.env.get("DASHSCOPE_API_KEY");
    const baseUrl = Deno.env.get("DASHSCOPE_BASE_URL") ??
      "https://llm-t2z6g1f4j7dhfig1.cn-beijing.maas.aliyuncs.com/compatible-mode/v1";
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!apiKey || !supabaseUrl || !supabaseAnonKey) return jsonResponse({ error: "AI service is not configured" }, 503);

    const authHeader = request.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing authorization" }, 401);

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return jsonResponse({ error: "Unauthorized" }, 401);
    const userId = userData.user.id;

    const body = await request.json().catch(() => null);
    const query = typeof body?.query === "string" ? body.query.trim() : "";
    if (!query) return jsonResponse({ error: "query is required" }, 400);

    const limit = Math.max(1, Math.min(20, Number.parseInt(String(body?.limit ?? 10), 10) || 10));
    const threshold = Math.max(0, Math.min(1, Number.parseFloat(String(body?.threshold ?? 0.3)) || 0.3));

    const embedRes = await fetch(`${baseUrl}/embeddings`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "text-embedding-v4", input: [query], dimensions: 1536 }),
    });
    if (!embedRes.ok) return jsonResponse({ error: `Embedding request failed: ${await embedRes.text()}` }, 502);
    const embedData = await embedRes.json();
    const queryEmbedding = embedData?.data?.[0]?.embedding;
    if (!Array.isArray(queryEmbedding)) return jsonResponse({ error: "Embedding is empty" }, 502);

    const { data, error: rpcError } = await supabase.rpc("explore_match_memories", {
      p_user_id: userId,
      query_embedding: queryEmbedding,
      match_threshold: threshold,
      match_count: limit,
    });
    if (rpcError) return jsonResponse({ error: rpcError.message }, 500);

    return jsonResponse({ memories: data ?? [] });
  }
  catch (err) {
    return jsonResponse({
      error: err instanceof Error ? err.message : String(err),
    }, 500);
  }
});
