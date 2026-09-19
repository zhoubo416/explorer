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

// 建议是对用户说的话，统一第二人称口吻，避免「用户……」的疏离感
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
    const userId = userData.user.id;

    const today = new Date().toISOString().slice(0, 10);

    // 建议按「目标+天」缓存：先取当前主目标，再查它当天有没有建议
    const goalRes = await supabase
      .from("explore_growth_goals")
      .select("id,title,description,stages,status,progress")
      .eq("user_id", userId)
      .neq("status", "archived")
      .order("is_main_goal", { ascending: false })
      // 存量数据可能没有 is_main_goal 标志：兜底取最新目标，与 Web 端 loadGoals 排序一致
      .order("created_at", { ascending: false })
      .limit(1);
    if (goalRes.error) return jsonResponse({ error: "Failed to load context" }, 500);
    const goal = goalRes.data?.[0];

    // 没有主目标时建议无处绑定：给静态引导，不落库
    if (!goal) return jsonResponse({ suggestion: "从一次对话开始，让探境更了解你。" });

    const { data: existing } = await supabase
      .from("explore_daily_suggestions")
      .select("content")
      .eq("user_id", userId)
      .eq("goal_id", goal.id)
      .eq("suggestion_date", today)
      .maybeSingle();
    if (existing?.content) return jsonResponse({ suggestion: existing.content });

    const memoriesRes = await supabase
      .from("explore_memory_items")
      .select("type,content")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(12);
    if (memoriesRes.error) return jsonResponse({ error: "Failed to load context" }, 500);
    const memories = memoriesRes.data ?? [];

    const activeStage = Array.isArray(goal.stages)
      ? (goal.stages as any[]).find((s) => s?.status === "active") ?? (goal.stages as any[])[0]
      : null;
    const context = JSON.stringify({
      goal: { title: goal.title, status: goal.status, progress: goal.progress },
      active_stage: activeStage ? { name: activeStage.name, actions: activeStage.actions } : null,
      recent_memories: memories.map((m) => ({ type: m.type, content: m.content })),
    });

    const systemPrompt = `你是“探境”的每日建议生成器。根据用户当前目标和近期记忆，生成一条今天就能做、足够小、可执行的建议。
只返回 JSON，不要 Markdown，格式：{"suggestion":"一句话建议（30字以内）"}
规则：
1. 建议要具体、可立刻开始，不要空泛（不要写“继续加油”）。
2. 优先基于当前阶段的未完成行动项给出下一步；没有阶段时，基于近期记忆给出一个小的推进动作。
3. 语气温和、不命令式。
4. 建议是对用户本人说的话，用第二人称「你」称呼（例如「你可以先……」），不要出现「用户」等第三人称称呼。`;

    const aiResponse = await callDeepSeek(deepseekApiKey, deepseekModel, [
      { role: "system", content: systemPrompt },
      { role: "user", content: `用户上下文：\n${context}` },
    ], 0.5);
    if (!aiResponse.ok) {
      return jsonResponse({ error: `DeepSeek failed: ${await aiResponse.text()}` }, 502);
    }
    const aiBody = await aiResponse.json();
    const raw = aiBody.choices?.[0]?.message?.content;
    const parsed = typeof raw === "string" ? extractJson(raw) : null;
    const suggestion = typeof parsed?.suggestion === "string" && parsed.suggestion.trim()
      ? normalizeVoice(parsed.suggestion)
      : "今天先完成一个足够小的下一步。";

    await supabase
      .from("explore_daily_suggestions")
      .upsert(
        { user_id: userId, suggestion_date: today, content: suggestion, goal_id: goal.id },
        { onConflict: "user_id,goal_id,suggestion_date" },
      );

    return jsonResponse({ suggestion });
  } catch (err) {
    return jsonResponse({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
