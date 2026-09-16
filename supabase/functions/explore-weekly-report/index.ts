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

const clampScore = (value: unknown): number => {
  const n = typeof value === "number" ? value : Number.parseFloat(String(value ?? ""));
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(10, Math.round(n * 10) / 10));
};

// 周报是写给用户本人看的，统一第二人称口吻，避免「用户……」的疏离感
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

  const now = new Date();
  const day = now.getUTCDay();
  const diffToMonday = (day + 6) % 7;
  const weekStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - diffToMonday));
  const weekEnd = new Date(weekStart.getTime() + 6 * 86400000);
  const weekStartStr = weekStart.toISOString().slice(0, 10);
  const weekEndStr = weekEnd.toISOString().slice(0, 10);
  const since = weekStart.toISOString();

  const [memoriesRes, goalsRes, messagesRes] = await Promise.all([
    supabase
      .from("explore_memory_items")
      .select("type,content,summary,importance,created_at")
      .eq("user_id", userId)
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(100),
    supabase
      .from("explore_growth_goals")
      .select("title,status,progress,success_definition")
      .eq("user_id", userId)
      .neq("status", "archived"),
    supabase
      .from("explore_conversations")
      .select("role,content")
      .eq("user_id", userId)
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(100),
  ]);

  if (memoriesRes.error) return jsonResponse({ error: memoriesRes.error.message }, 500);
  if (goalsRes.error) return jsonResponse({ error: goalsRes.error.message }, 500);
  if (messagesRes.error) return jsonResponse({ error: messagesRes.error.message }, 500);

  const memories = memoriesRes.data ?? [];
  const goals = goalsRes.data ?? [];
  const messages = [...(messagesRes.data ?? [])].reverse();

  if (memories.length === 0 && goals.length === 0) {
    return jsonResponse({ report: null });
  }

  const context = JSON.stringify({
    goals: goals.map((g) => ({ title: g.title, status: g.status, progress: g.progress, success_definition: g.success_definition })),
    memories: memories.map((m) => ({ type: m.type, content: m.content, summary: m.summary, importance: m.importance })),
    recent_messages: messages.slice(-30).map((m) => ({ role: m.role, content: m.content })),
  });

  const systemPrompt = `你是"探境"的周报生成器。基于用户本周的数据，生成一份诚实、具体的成长周报。
只返回 JSON，不要 Markdown，格式：
{"score":0到10,"completed":["本周完成的事项"],"insight":"一个关键发现","nextSteps":["下一步建议"]}
规则：
1. score 依据实际行动与进展，而非字数或情绪。
2. completed 用过去时、具体的事项，最多 5 条。
3. insight 一句话、具体不空泛。
4. nextSteps 1-3 条，足够小、可执行。
5. 周报是写给用户本人看的，始终用第二人称「你」称呼（例如「你本周……」「你可以……」），不要出现「用户」等第三人称称呼。`;

  const aiResponse = await callDeepSeek(deepseekApiKey, deepseekModel, [
    { role: "system", content: systemPrompt },
    { role: "user", content: `用户本周数据如下：\n${context}` },
  ], 0.5);
  if (!aiResponse.ok) {
    return jsonResponse({ error: `DeepSeek request failed: ${await aiResponse.text()}` }, 502);
  }
  const aiBody = await aiResponse.json();
  const raw = aiBody.choices?.[0]?.message?.content;
  if (typeof raw !== "string") return jsonResponse({ error: "AI response is empty" }, 502);

  const parsed = extractJson(raw);
  const report = {
    score: clampScore(parsed?.score),
    completed: Array.isArray(parsed?.completed)
      ? parsed.completed.filter((x) => typeof x === "string").map((x) => normalizeVoice(String(x))).slice(0, 5)
      : [],
    insight: typeof parsed?.insight === "string" ? normalizeVoice(parsed.insight) : "",
    nextSteps: Array.isArray(parsed?.nextSteps)
      ? parsed.nextSteps.filter((x) => typeof x === "string").map((x) => normalizeVoice(String(x))).slice(0, 3)
      : [],
  };

  const { error: saveError } = await supabase
    .from("explore_weekly_reports")
    .upsert({
      user_id: userId,
      week_start: weekStartStr,
      week_end: weekEndStr,
      score: report.score,
      completed: report.completed,
      insight: report.insight,
      next_steps: report.nextSteps,
    }, { onConflict: "user_id,week_start" });
  if (saveError) return jsonResponse({ error: saveError.message }, 500);

  return jsonResponse({ report, week: { start: weekStartStr, end: weekEndStr } });
  }
  catch (err) {
    return jsonResponse({
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    }, 500);
  }
});
