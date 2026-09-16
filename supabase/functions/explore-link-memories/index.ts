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

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !supabaseAnonKey) return jsonResponse({ error: "Service not configured" }, 503);

    const authHeader = request.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing authorization" }, 401);
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return jsonResponse({ error: "Unauthorized" }, 401);
    const userId = userData.user.id;

    const body = await request.json().catch(() => null);
    const memoryId = body?.memory_id;
    if (typeof memoryId !== "string") return jsonResponse({ error: "memory_id is required" }, 400);

    const { data: mem, error: memError } = await supabase
      .from("explore_memory_items")
      .select("embedding,user_id")
      .eq("id", memoryId)
      .eq("user_id", userId)
      .single();
    if (memError || !mem) return jsonResponse({ error: "Memory not found" }, 404);

    let linked = 0;

    // 记忆 ↔ 目标：通过 growth_events 找到关联目标并写入关系图谱
    const { data: events } = await supabase
      .from("explore_growth_events")
      .select("goal_id")
      .eq("memory_id", memoryId)
      .eq("user_id", userId)
      .limit(1);
    const goalId = events?.[0]?.goal_id;
    if (goalId) {
      const { error: goalRelError } = await supabase.from("explore_memory_relations").upsert(
        { user_id: userId, source_id: memoryId, target_goal_id: goalId, relation_type: "related_to" },
        { onConflict: "source_id,target_goal_id,relation_type" },
      );
      if (!goalRelError) linked++;
    }

    if (!mem.embedding) return jsonResponse({ linked });

    let embedding: number[] | null = null;
    if (typeof mem.embedding === "string") {
      try {
        embedding = JSON.parse(mem.embedding);
      } catch {
        embedding = null;
      }
    } else if (Array.isArray(mem.embedding)) {
      embedding = mem.embedding;
    }
    if (!embedding || embedding.length === 0) return jsonResponse({ linked });

    const { data: similar, error: rpcError } = await supabase.rpc("explore_match_memories", {
      p_user_id: userId,
      query_embedding: embedding,
      match_threshold: 0.45,
      match_count: 5,
    });
    if (rpcError) return jsonResponse({ error: rpcError.message }, 500);

    for (const s of similar ?? []) {
      if (s.id === memoryId) continue;
      const { error: relError } = await supabase.from("explore_memory_relations").upsert(
        { user_id: userId, source_id: memoryId, target_id: s.id, relation_type: "similar" },
        { onConflict: "source_id,target_id,relation_type" },
      );
      if (!relError) linked++;
    }

    return jsonResponse({ linked });
  }
  catch (err) {
    return jsonResponse({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
