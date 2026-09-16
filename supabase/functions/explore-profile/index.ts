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

const callDeepSeek = async (apiKey: string, model: string, messages: unknown[], temperature: number): Promise<Response> => {
  const maxAttempts = 3;
  let lastError = "DeepSeek request failed";
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const res = await fetch("https://api.deepseek.com/chat/completions", {
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

const strList = (v: unknown): string[] =>
  Array.isArray(v) ? v.filter((x) => typeof x === "string").map((x) => String(x)).slice(0, 5) : [];

// 画像里成句的字段（ai_summary/current_stage）是对用户说的话，统一第二人称口吻
const normalizeVoice = (text: string): string =>
  text
    .replace(/这个用户|该用户|用户/g, "你")
    .replace(/\s+/g, " ")
    .trim();

const clamp = (value: unknown): number => {
  const n = typeof value === "number" ? value : Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(100, Math.round(n)));
};

const normalizeGrowthItems = (v: unknown, kind: "dimension" | "composition"): Record<string, unknown>[] => {
  if (!Array.isArray(v)) return [];
  return v
    .filter((x) => x && typeof x === "object" && typeof (x as Record<string, unknown>).name === "string")
    .slice(0, 5)
    .map((x) => {
      const item = x as Record<string, unknown>;
      const name = String(item.name).trim();
      const base: Record<string, unknown> = { name };
      if (kind === "dimension") {
        base.score = clamp(item.score);
        if (typeof item.evidence === "string" && item.evidence.trim()) base.evidence = item.evidence.trim();
      } else {
        base.ratio = clamp(item.ratio);
        if (typeof item.insight === "string" && item.insight.trim()) base.insight = item.insight.trim();
      }
      return base;
    })
    .filter((x) => x.name);
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

    const [memoriesRes, goalsRes, messagesRes] = await Promise.all([
      supabase
        .from("explore_memory_items")
        .select("type,content,summary,importance")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(100),
      supabase
        .from("explore_growth_goals")
        .select("title,description,status,progress")
        .eq("user_id", userId)
        .neq("status", "archived"),
      supabase
        .from("explore_conversations")
        .select("role,content")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(80),
    ]);

    if (memoriesRes.error || goalsRes.error || messagesRes.error) {
      return jsonResponse({ error: "Failed to load user data" }, 500);
    }

    const memories = memoriesRes.data ?? [];
    const goals = goalsRes.data ?? [];
    const messages = (messagesRes.data ?? []).reverse();
    if (memories.length === 0 && goals.length === 0) return jsonResponse({ profile: null });

    const context = JSON.stringify({
      memories: memories.map((m) => ({ type: m.type, content: m.content })),
      goals: goals.map((g) => ({ title: g.title, status: g.status, progress: g.progress })),
      recent_messages: messages.slice(-20).map((m) => ({ role: m.role, content: m.content })),
    });

    const systemPrompt = `你是"探境"的用户画像提炼器。根据用户的记忆、目标和对话，提炼出简洁、真实的用户画像。
只返回 JSON，不要 Markdown，格式：
{
  "personality":["性格特质"],
  "values":["价值观"],
  "interests":["兴趣方向"],
  "strengths":["优势"],
  "weaknesses":["待改进之处"],
  "current_stage":"当前成长阶段",
  "ai_summary":"一句话总结这个人",
  "growth_dimensions":[{"name":"能力维度","score":0到100,"evidence":"依据"}],
  "growth_composition":[{"name":"成长构成项","ratio":0到100,"insight":"一句洞察"}]
}
规则：
1. 只提炼有明确证据支撑的，不要编造。
2. 每项 1-3 个，用简短词组（2-6 个字）。
3. 某项信息不足时用空数组。
4. growth_dimensions 是用户当前正在发展或已具备的能力维度（如技术能力/产品能力/商业能力/沟通表达/执行力），给 3-5 项，score 为该维度相对成熟度，evidence 用一条记忆或目标作为依据。
5. growth_composition 是用户近期成长的来源构成（如技术学习/实践产出/反思沉淀/情绪调适），给 3-5 项，ratio 为该来源的占比（合计约 100），insight 一句话说明这个构成背后的信号。
6. 不要用关键词硬凑分数，要基于语义和证据综合判断。
7. current_stage 和 ai_summary 是对用户本人说的话，用第二人称「你」称呼（例如「你正处在……」「你是一个……」），不要出现「用户」等第三人称称呼。`;

    const aiResponse = await callDeepSeek(deepseekApiKey, deepseekModel, [
      { role: "system", content: systemPrompt },
      { role: "user", content: `用户数据：\n${context}` },
    ], 0.4);
    if (!aiResponse.ok) {
      return jsonResponse({ error: `DeepSeek failed: ${await aiResponse.text()}` }, 502);
    }
    const aiBody = await aiResponse.json();
    const raw = aiBody.choices?.[0]?.message?.content;
    const parsed = typeof raw === "string" ? extractJson(raw) : null;

    const profile = {
      personality: strList(parsed?.personality),
      values: strList(parsed?.values),
      interests: strList(parsed?.interests),
      strengths: strList(parsed?.strengths),
      weaknesses: strList(parsed?.weaknesses),
      current_stage: typeof parsed?.current_stage === "string" ? normalizeVoice(parsed.current_stage) : "",
      ai_summary: typeof parsed?.ai_summary === "string" ? normalizeVoice(parsed.ai_summary) : "",
      growth_dimensions: normalizeGrowthItems(parsed?.growth_dimensions, "dimension"),
      growth_composition: normalizeGrowthItems(parsed?.growth_composition, "composition"),
    };

    const { error: upsertError } = await supabase.from("explore_user_profiles").upsert({
      user_id: userId,
      personality: profile.personality,
      values: profile.values,
      interests: profile.interests,
      strengths: profile.strengths,
      weaknesses: profile.weaknesses,
      current_stage: profile.current_stage,
      ai_summary: profile.ai_summary,
      growth_dimensions: profile.growth_dimensions,
      growth_composition: profile.growth_composition,
    });
    if (upsertError) return jsonResponse({ error: upsertError.message }, 500);

    return jsonResponse({ profile });
  }
  catch (err) {
    return jsonResponse({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
