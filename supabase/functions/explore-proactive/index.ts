import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
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

const NEGATIVE_EMOTION = /放弃|没意义|太累|很累|焦虑|沮丧|撑不住|不想坚持|迷茫/;

// 主动消息是对用户本人说的话，统一第二人称口吻，避免「用户……」的疏离感
const normalizeVoice = (text: string): string =>
  text
    .replace(/这个用户|该用户|用户/g, "你")
    .replace(/\s+/g, " ")
    .trim();

const processUser = async (
  supabase: SupabaseClient,
  userId: string,
  deepseekApiKey: string,
  deepseekModel: string,
): Promise<Record<string, unknown> | null> => {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString();
  const fourteenDaysAgo = new Date(Date.now() - 14 * 86400000).toISOString();
  const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString();

  const [goalsRes, memoriesRes, lastReflectionRes] = await Promise.all([
    supabase
      .from("explore_growth_goals")
      .select("id,title,status,progress,updated_at,stages")
      .eq("user_id", userId)
      .neq("status", "archived"),
    supabase
      .from("explore_memory_items")
      .select("type,content,summary,importance,emotion,created_at")
      .eq("user_id", userId)
      .gte("created_at", thirtyDaysAgo)
      .order("created_at", { ascending: false })
      .limit(100),
    supabase
      .from("explore_ai_actions")
      .select("created_at")
      .eq("user_id", userId)
      .eq("type", "reflection")
      .order("created_at", { ascending: false })
      .limit(1),
  ]);

  if (goalsRes.error || memoriesRes.error || lastReflectionRes.error) return null;

  const goals = goalsRes.data ?? [];
  const memories = memoriesRes.data ?? [];

  const stagnantGoals = goals.filter(
    (g) => g.status === "active" && g.updated_at && g.updated_at < thirtyDaysAgo,
  );
  const breakthroughs = memories.filter(
    (m) =>
      (m.type === "achievement" || m.type === "event") &&
      Number(m.importance ?? 0) >= 80 &&
      m.created_at >= sevenDaysAgo,
  );
  const negativeEmotions = memories.filter(
    (m) =>
      (m.type === "emotion" || m.type === "reflection") &&
      m.created_at >= fourteenDaysAgo &&
      (NEGATIVE_EMOTION.test(String(m.content ?? "")) ||
        (typeof m.emotion === "string" && NEGATIVE_EMOTION.test(m.emotion))),
  );

  const thinking = memories.filter(
    (m) => (m.type === "reflection" || m.type === "thought") && m.created_at >= fourteenDaysAgo,
  );
  const acting = memories.filter(
    (m) => (m.type === "achievement" || m.type === "event") && m.created_at >= fourteenDaysAgo,
  );
  const rhythmOff = thinking.length >= 3 && acting.length === 0;

  const activeGoal = goals.find((g) => g.status === "active");
  const activeStage = activeGoal && Array.isArray(activeGoal.stages)
    ? (activeGoal.stages as any[]).find((s) => s?.status === "active")
    : null;
  const pendingActions = activeStage
    ? ((activeStage.actions as any[]) ?? []).filter((a) => !a.done)
    : [];
  const recentActing = memories.filter(
    (m) => (m.type === "achievement" || m.type === "event") && m.created_at >= sevenDaysAgo,
  );
  const actionStale = activeStage && pendingActions.length > 0 && recentActing.length === 0;
  const lastReflection = lastReflectionRes?.data?.[0]?.created_at;
  const reflectionDue = !lastReflection || lastReflection < sevenDaysAgo;

  let trigger: { kind: string; title: string; reason: string; content: string } | null = null;
  if (negativeEmotions.length >= 2) {
    trigger = {
      kind: "encouragement",
      title: "情绪陪伴",
      reason: "近两周多次出现负面情绪表达",
      content: negativeEmotions.map((m) => m.content).join(" / "),
    };
  }
  else if (stagnantGoals.length > 0) {
    const goal = stagnantGoals[0];
    trigger = {
      kind: "warning",
      title: "目标停滞提醒",
      reason: `目标「${goal.title}」已超过 30 天没有推进`,
      content: `目标「${goal.title}」最近没有进展，可能需要重新调整或拆小下一步。`,
    };
  }
  else if (rhythmOff) {
    trigger = {
      kind: "insight",
      title: "节奏提醒",
      reason: "近期输入多、实践少",
      content: `近两周思考/反思有 ${thinking.length} 条，但还没有行动或成果记录。`,
    };
  }
  else if (actionStale) {
    trigger = {
      kind: "reminder",
      title: "下一步提醒",
      reason: `当前阶段「${activeStage.name}」还有 ${pendingActions.length} 个行动未完成`,
      content: pendingActions[0].content,
    };
  }
  else if (breakthroughs.length > 0) {
    trigger = {
      kind: "encouragement",
      title: "成长突破",
      reason: "近期有一个值得被看见的成长节点",
      content: breakthroughs[0].content,
    };
  }
  else if (reflectionDue && memories.length > 0) {
    trigger = {
      kind: "reflection",
      title: "深度反思",
      reason: "每周成长回顾",
      content: "回顾这段时间的经历与感受",
    };
  }

  if (!trigger) return null;

  const systemPrompt = `你是"探境"的主动消息生成器。根据触发原因和用户背景，生成一条温和、具体、不打扰的主动消息。
只返回 JSON，不要 Markdown，格式：{"content":"给用户的一句话消息（35字以内）"}
规则：
- 若类型是"深度反思"，生成一个开放、有深度的自我反思问题，不要给行动建议、不要催促。
- 其它类型：先共情或肯定，再给一个足够小的下一步；不要命令式，不要空泛。
- 消息是对用户本人说的话，用第二人称「你」称呼（例如「你最近……」），不要出现「用户」等第三人称称呼。`;

  const aiResponse = await callDeepSeek(deepseekApiKey, deepseekModel, [
    { role: "system", content: systemPrompt },
    {
      role: "user",
      content: JSON.stringify({ trigger: trigger.title, reason: trigger.reason, context: trigger.content }),
    },
  ], 0.6);
  if (!aiResponse.ok) return null;
  const aiBody = await aiResponse.json();
  const raw = aiBody.choices?.[0]?.message?.content;
  const parsed = typeof raw === "string" ? extractJson(raw) : null;
  const message = typeof parsed?.content === "string" ? normalizeVoice(parsed.content) : trigger.content;

  const { data: inserted, error: insertError } = await supabase
    .from("explore_ai_actions")
    .insert({
      user_id: userId,
      type: trigger.kind,
      content: message,
      trigger_reason: trigger.reason,
      status: "pending",
    })
    .select()
    .single();
  if (insertError || !inserted) return null;
  return inserted as Record<string, unknown>;
};

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const deepseekApiKey = Deno.env.get("DEEPSEEK_API_KEY");
    const deepseekModel = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (!supabaseUrl || !supabaseAnonKey || !deepseekApiKey) {
      return jsonResponse({ error: "AI service is not configured" }, 503);
    }

    const isScheduled = Boolean(cronSecret) && request.headers.get("x-cron-secret") === cronSecret;

    if (isScheduled) {
      if (!serviceRoleKey) return jsonResponse({ error: "Service role not configured" }, 503);
      const serviceClient = createClient(supabaseUrl, serviceRoleKey);
      const { data: usersData, error: listError } = await serviceClient.auth.admin.listUsers({
        page: 1,
        perPage: 200,
      });
      if (listError) return jsonResponse({ error: listError.message }, 500);
      const users = usersData?.users ?? [];
      const created: Record<string, unknown>[] = [];
      for (const user of users) {
        const inserted = await processUser(serviceClient, user.id, deepseekApiKey, deepseekModel);
        if (inserted) created.push(inserted);
      }
      return jsonResponse({ scheduled: true, processed: users.length, created: created.length });
    }

    const authHeader = request.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing authorization" }, 401);
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return jsonResponse({ error: "Unauthorized" }, 401);

    const inserted = await processUser(supabase, userData.user.id, deepseekApiKey, deepseekModel);
    return jsonResponse({ actions: inserted ? [inserted] : [] });
  }
  catch (err) {
    return jsonResponse({
      error: err instanceof Error ? err.message : String(err),
    }, 500);
  }
});
