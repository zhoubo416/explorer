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

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";

const callDeepSeek = async (apiKey: string, model: string, messages: unknown[], temperature: number): Promise<Response> => {
  const maxAttempts = 3;
  let lastError = "DeepSeek request failed";
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const res = await fetch(DEEPSEEK_URL, {
        method: "POST",
        headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model, temperature, messages }),
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (res.ok) return res;
      if (res.status !== 429 && res.status < 500) return res;
      lastError = `DeepSeek HTTP ${res.status}`;
    } catch (error) {
      clearTimeout(timer);
      lastError = error instanceof Error ? error.message : String(error);
    }
    if (attempt < maxAttempts - 1) {
      await new Promise((resolve) => setTimeout(resolve, 2000 * Math.pow(2, attempt)));
    }
  }
  return new Response(JSON.stringify({ error: lastError }), {
    status: 502,
    headers: { "Content-Type": "application/json" },
  });
};

const extractJson = (raw: string): Record<string, unknown> | null => {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)\s*```/i)?.[1] ?? raw;
  const start = fenced.indexOf("{");
  const end = fenced.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(fenced.slice(start, end + 1));
  } catch {
    return null;
  }
};

// 总结是写给用户本人看的，统一第二人称口吻，避免「用户……」的疏离感
const normalizeVoice = (text: string): string =>
  text
    .replace(/这个用户|该用户|用户/g, "你")
    .replace(/\s+/g, " ")
    .trim();

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const deepseekApiKey = Deno.env.get("DEEPSEEK_API_KEY");
    const deepseekModel = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
    if (!supabaseUrl || !supabaseAnonKey || !deepseekApiKey) {
      return jsonResponse({ error: "AI service is not configured" }, 503);
    }

    const authHeader = request.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing authorization" }, 401);
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return jsonResponse({ error: "Unauthorized" }, 401);

    const { data: rows, error: memoriesError } = await supabase
      .from("explore_memory_items")
      .select("type,content,summary,created_at")
      .eq("user_id", userData.user.id)
      .order("created_at", { ascending: true });
    if (memoriesError) return jsonResponse({ error: memoriesError.message }, 500);

    const memories = rows ?? [];
    if (memories.length < 3) return jsonResponse({ summary: null });

    const context = JSON.stringify(
      memories.map((m) => ({ time: m.created_at, type: m.type, content: m.content })),
    );

    const systemPrompt = `你是"探境"的成长轨迹总结器。根据用户按时间排列的记忆，生成一段成长"阶段总结"。
只返回 JSON，不要 Markdown，格式：{"summary":"2-3 句话，概括这段成长轨迹的主题、转变和当前方向"}
规则：具体、不空泛、基于记忆事实，不要罗列条目；总结是写给用户本人看的，用第二人称「你」称呼，不要出现「用户」等第三人称称呼。`;

    const aiResponse = await callDeepSeek(deepseekApiKey, deepseekModel, [
      { role: "system", content: systemPrompt },
      { role: "user", content: `用户记忆如下：\n${context}` },
    ], 0.5);
    if (!aiResponse.ok) {
      return jsonResponse({ error: `DeepSeek request failed: ${await aiResponse.text()}` }, 502);
    }
    const aiBody = await aiResponse.json();
    const raw = aiBody.choices?.[0]?.message?.content;
    const parsed = typeof raw === "string" ? extractJson(raw) : null;
    const summary = typeof parsed?.summary === "string" ? normalizeVoice(parsed.summary) : null;

    return jsonResponse({ summary });
  }
  catch (err) {
    return jsonResponse({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
