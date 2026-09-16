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

// 分析是写给用户本人看的，统一第二人称口吻，避免「用户……」的疏离感
const normalizeVoice = (text: string): string =>
  text
    .replace(/这个用户|该用户|用户/g, "你")
    .replace(/\s+/g, " ")
    .trim();

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
    const userId = userData.user.id;

    const body = await request.json().catch(() => null);
    const goalId = body?.goal_id;
    if (typeof goalId !== "string") return jsonResponse({ error: "goal_id is required" }, 400);

    const { data: goal, error: goalError } = await supabase
      .from("explore_growth_goals")
      .select("id,title,description,status,progress,success_definition")
      .eq("id", goalId)
      .eq("user_id", userId)
      .single();
    if (goalError || !goal) return jsonResponse({ error: "Goal not found" }, 404);

    const [memoriesRes, messagesRes] = await Promise.all([
      supabase
        .from("explore_memory_items")
        .select("type,content,summary,importance,created_at")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(30),
      supabase
        .from("explore_conversations")
        .select("role,content")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(30),
    ]);

    if (memoriesRes.error) return jsonResponse({ error: memoriesRes.error.message }, 500);
    if (messagesRes.error) return jsonResponse({ error: messagesRes.error.message }, 500);

    const memories = memoriesRes.data ?? [];
    const messages = [...(messagesRes.data ?? [])].reverse();

    const context = JSON.stringify({
      goal: {
        title: goal.title,
        description: goal.description,
        status: goal.status,
        progress: goal.progress,
        success_definition: goal.success_definition,
      },
      memories: memories.map((m) => ({ type: m.type, content: m.content, summary: m.summary, importance: m.importance })),
      recent_messages: messages.slice(-15).map((m) => ({ role: m.role, content: m.content })),
    });

    const systemPrompt = `你是"探境"的目标推理引擎。针对用户的一个具体目标，做诚实、具体、可执行的分析。
只返回 JSON，不要 Markdown，格式：
{"summary":"阶段总结（1-2句）","observation":"关键观察（1-2句）","suggestion":"建议（1-2句）","actions":["行动1","行动2","行动3"]}
规则：
1. summary 依据当前进度和状态，不空泛。
2. observation 指出一个真实信号或可能的问题。
3. suggestion 给一条方向性建议。
4. actions 1-3 条，足够小、可执行。
5. 分析是写给用户本人看的，用第二人称「你」称呼，不要出现「用户」等第三人称称呼。`;

    const aiResponse = await callDeepSeek(deepseekApiKey, deepseekModel, [
      { role: "system", content: systemPrompt },
      { role: "user", content: `目标与用户数据如下：\n${context}` },
    ], 0.5);
    if (!aiResponse.ok) {
      return jsonResponse({ error: `DeepSeek request failed: ${await aiResponse.text()}` }, 502);
    }
    const aiBody = await aiResponse.json();
    const raw = aiBody.choices?.[0]?.message?.content;
    if (typeof raw !== "string") return jsonResponse({ error: "AI response is empty" }, 502);

    const parsed = extractJson(raw);
    const analysis = {
      summary: typeof parsed?.summary === "string" ? normalizeVoice(parsed.summary) : "",
      observation: typeof parsed?.observation === "string" ? normalizeVoice(parsed.observation) : "",
      suggestion: typeof parsed?.suggestion === "string" ? normalizeVoice(parsed.suggestion) : "",
      actions: Array.isArray(parsed?.actions)
        ? parsed.actions.filter((x) => typeof x === "string").map((x) => normalizeVoice(String(x))).slice(0, 3)
        : [],
    };

    const { error: updateError } = await supabase
      .from("explore_growth_goals")
      .update({ ai_summary: JSON.stringify(analysis) })
      .eq("id", goalId)
      .eq("user_id", userId);
    if (updateError) return jsonResponse({ error: updateError.message }, 500);

    return jsonResponse({ analysis });
  }
  catch (err) {
    return jsonResponse({
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    }, 500);
  }
});
