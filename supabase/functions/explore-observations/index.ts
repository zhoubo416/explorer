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

const clamp = (value: unknown, min = 0, max = 100): number => {
  const n = typeof value === "number" ? value : Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(n)) return Math.round((min + max) / 2);
  return Math.max(min, Math.min(max, Math.round(n)));
};

// 观察是对用户说的话，统一第二人称口吻，避免「用户……」的疏离感
const normalizeVoice = (text: string): string =>
  text
    .replace(/这个用户|该用户|用户/g, "你")
    .replace(/\s+/g, " ")
    .trim();

Deno.serve(async (request) => {
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

  const [memoriesRes, goalsRes, messagesRes] = await Promise.all([
    supabase
      .from("explore_memory_items")
      .select("type,content,summary,created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(30),
    supabase
      .from("explore_growth_goals")
      .select("title,description,status,progress,success_definition")
      .eq("user_id", userId)
      .neq("status", "archived")
      .order("is_main_goal", { ascending: false })
      // 非主目标间的顺序固定为最新在前，与 Web 端 loadGoals 排序一致
      .order("created_at", { ascending: false })
      .limit(10),
    supabase
      .from("explore_conversations")
      .select("role,content")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(50),
  ]);

  if (memoriesRes.error) return jsonResponse({ error: memoriesRes.error.message }, 500);
  if (goalsRes.error) return jsonResponse({ error: goalsRes.error.message }, 500);
  if (messagesRes.error) return jsonResponse({ error: messagesRes.error.message }, 500);

  const memories = memoriesRes.data ?? [];
  const goals = goalsRes.data ?? [];
  const messages = [...(messagesRes.data ?? [])].reverse();

  if (memories.length === 0 && goals.length === 0) {
    return jsonResponse({ observations: [] });
  }

  const context = JSON.stringify({
    goals: goals.map((g) => ({
      title: g.title,
      description: g.description,
      status: g.status,
      progress: g.progress,
    })),
    memories: memories.map((m) => ({ type: m.type, content: m.content, summary: m.summary })),
    recent_messages: messages.slice(-20).map((m) => ({ role: m.role, content: m.content })),
  });

  const systemPrompt = `你是"探境"的成长观察器。根据用户的目标、记忆和最近对话，提炼 1 到 3 条有洞察力的观察。
要求：
1. 具体、基于事实，不要泛泛而谈（不要写"你在成长"这类空话）。
2. 每条观察 1-2 句话，指出一个趋势、节奏变化或值得注意的信号。
3. 观察是对用户本人说的话，始终用第二人称「你」直接称呼（例如「你最近……」「你已经开始……」），不要出现「用户」「该用户」等第三人称称呼。
4. 只返回 JSON，不要 Markdown，格式：{"observations":[{"content":"观察内容","confidence":0到100}]}`;

  const aiResponse = await callDeepSeek(deepseekApiKey, deepseekModel, [
    { role: "system", content: systemPrompt },
    { role: "user", content: `用户数据如下：\n${context}` },
  ], 0.6);
  if (!aiResponse.ok) {
    return jsonResponse({ error: `DeepSeek request failed: ${await aiResponse.text()}` }, 502);
  }
  const aiBody = await aiResponse.json();
  const raw = aiBody.choices?.[0]?.message?.content;
  if (typeof raw !== "string") return jsonResponse({ error: "AI response is empty" }, 502);

  const parsed = extractJson(raw);
  const items = Array.isArray(parsed?.observations) ? parsed.observations : [];
  const sourceMemories = memories.slice(0, 5).map((m) => ({ type: m.type, content: m.content }));

  const inserted: unknown[] = [];
  for (const item of items.slice(0, 3)) {
    const record = item as Record<string, unknown> | null;
    const content = typeof record?.content === "string" ? normalizeVoice(record.content) : "";
    if (!content) continue;
    const { data: row, error: insertError } = await supabase
      .from("explore_ai_observations")
      .insert({
        user_id: userId,
        content,
        confidence: clamp(record?.confidence, 0, 100),
        source_memories: sourceMemories,
      })
      .select()
      .single();
    if (!insertError && row) inserted.push(row);
  }

  return jsonResponse({ observations: inserted });
});
