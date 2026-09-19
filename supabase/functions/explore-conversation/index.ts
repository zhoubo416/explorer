import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseModelResult, type ModelResult } from "./model-result.ts";
import { buildSystemPrompt } from "./prompt.ts";
import { createReplyStream } from "./stream-reply.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ChatRow = {
  role: "user" | "assistant" | "system";
  content: string;
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const sseResponse = (stream: ReadableStream<Uint8Array>) =>
  new Response(stream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";

const DASHSCOPE_BASE_URL_DEFAULT =
  "https://llm-t2z6g1f4j7dhfig1.cn-beijing.maas.aliyuncs.com/compatible-mode/v1";

const MOOD_STAGE_INSTRUCTIONS = [
  "当前应进行第一层（情绪理解）：先真诚共情，再问“最近发生了什么，让你产生这个想法？”。",
  "当前应进行第二层（原因探索）：在理解用户的具体原因后，问“如果现在已经有一些成果或用户反馈，你还会想继续吗？”。",
  "当前应进行第三层（区分问题）：问“你想放弃的是这个方向，还是只是当前的方法？”。",
  "三层已完成：现在基于用户回答给出判断与建议（短期挫折→调整策略、降低目标或重新行动；方向确实变了→温和建议重新评估），不要继续追问层级问题。",
];

const embedText = async (
  apiKey: string,
  baseUrl: string,
  text: string,
): Promise<number[] | null> => {
  try {
    const res = await fetch(`${baseUrl}/embeddings`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "text-embedding-v4", input: [text], dimensions: 1536 }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return data?.data?.[0]?.embedding ?? null;
  } catch {
    return null;
  }
};

const linkMemories = async (
  supabase: any,
  userId: string,
  memoryId: string,
  embedding: number[],
): Promise<void> => {
  try {
    const { data: similar, error } = await supabase.rpc("explore_match_memories", {
      p_user_id: userId,
      query_embedding: embedding,
      match_threshold: 0.45,
      match_count: 5,
    });
    if (error || !similar?.length) return;
    for (const s of similar as Record<string, unknown>[]) {
      if (s.id === memoryId) continue;
      await supabase.from("explore_memory_relations").upsert(
        { user_id: userId, source_id: memoryId, target_id: s.id, relation_type: "similar" },
        { onConflict: "source_id,target_id,relation_type" },
      );
    }
  } catch {
    // 关联失败不阻断对话
  }
};

type GoalUpdate = {
  done_actions: string[];
  advance_stage: boolean;
  goal_completed: boolean;
  note: string;
};

const applyGoalUpdate = (
  stages: unknown[],
  update: GoalUpdate,
): { stages: unknown[]; status: string; progress: number } | null => {
  if (!Array.isArray(stages) || stages.length === 0) return null;
  const activeIndex = stages.findIndex((s) => (s as Record<string, unknown>)?.status === "active");
  if (activeIndex < 0) return null;
  const active = stages[activeIndex] as Record<string, unknown>;
  const actions = Array.isArray(active?.actions) ? active.actions as Record<string, unknown>[] : [];
  for (const content of update.done_actions) {
    for (const action of actions) {
      if (action.done) continue;
      const c = String(action.content ?? "");
      if (c && (c === content || c.includes(content) || content.includes(c))) {
        action.done = true;
      }
    }
  }
  const allDone = actions.length > 0 && actions.every((a) => a.done === true);
  let completed = false;
  if (update.goal_completed) {
    for (const s of stages) (s as Record<string, unknown>).status = "completed";
    completed = true;
  } else if (update.advance_stage || allDone) {
    (active as Record<string, unknown>).status = "completed";
    if (activeIndex + 1 < stages.length) {
      (stages[activeIndex + 1] as Record<string, unknown>).status = "active";
    }
  }
  const completedCount = stages.filter((s) => (s as Record<string, unknown>)?.status === "completed").length;
  const progress = completed ? 100 : Math.round((completedCount / stages.length) * 100);
  return { stages, status: completed ? "completed" : "active", progress };
};

type SideEffectContext = {
  supabase: any;
  userId: string;
  sessionId: string;
  mode: string;
  moodStage: number;
  goal: any;
  result: ModelResult;
  dashscopeApiKey?: string;
  dashscopeBaseUrl: string;
};

// 一轮对话的全部副作用：助手回复落库、会话预览、mood_stage、记忆与成长事件、
// 向量化与关系关联、目标阶段与状态更新。流式出口在模型输出结束后调用它。
const applyTurnSideEffects = async (ctx: SideEffectContext): Promise<Record<string, unknown>> => {
  const { supabase, userId, sessionId, mode, moodStage, goal, result, dashscopeApiKey, dashscopeBaseUrl } = ctx;

  // 1) 落库助手回复并更新会话预览
  const { error: replyError } = await supabase.from("explore_conversations").insert({
    session_id: sessionId,
    user_id: userId,
    role: "assistant",
    content: result.reply,
  });
  if (replyError) throw new Error(replyError.message);
  await supabase
    .from("explore_conversation_sessions")
    .update({ preview: result.reply })
    .eq("id", sessionId)
    .eq("user_id", userId);

  if (mode === "low_mood") {
    await supabase
      .from("explore_conversation_sessions")
      .update({ mood_stage: Math.min(moodStage + 1, 3) })
      .eq("id", sessionId)
      .eq("user_id", userId);
  }

  // 2) 记忆落库链（记忆 + 成长事件 + 向量化 + 关系关联）统一收进后端
  let savedMemory: Record<string, unknown> | null = null;
  if (result.memory) {
    const mem = result.memory;
    const { data: memRow, error: memErr } = await supabase
      .from("explore_memory_items")
      .insert({
        user_id: userId,
        type: mem.type,
        content: mem.content,
        summary: mem.summary ?? null,
        importance: mem.importance,
        emotion: mem.emotion ?? null,
      })
      .select("id")
      .single();
    if (!memErr && memRow) {
      savedMemory = { id: memRow.id, type: mem.type, content: mem.content };
      if (goal?.id) {
        await supabase.from("explore_growth_events").insert({
          user_id: userId,
          goal_id: goal.id,
          memory_id: memRow.id,
          impact_score: mem.importance,
          description: mem.content,
        });
        await supabase.from("explore_memory_relations").upsert(
          { user_id: userId, source_id: memRow.id, target_goal_id: goal.id, relation_type: "related_to" },
          { onConflict: "source_id,target_goal_id,relation_type" },
        );
      }
      if (dashscopeApiKey) {
        const embedding = await embedText(dashscopeApiKey, dashscopeBaseUrl, mem.content);
        if (embedding) {
          await supabase.from("explore_memory_items").update({ embedding }).eq("id", memRow.id);
          await linkMemories(supabase, userId, memRow.id, embedding);
        }
      }
    }
  }

  // 3) 目标阶段/行动项更新统一收进后端
  let updatedGoal: Record<string, unknown> | null = null;
  if (result.goal_update && goal?.id) {
    const stages = Array.isArray(goal.stages) ? goal.stages : [];
    const applied = applyGoalUpdate(stages, result.goal_update);
    if (applied) {
      const { data: updated, error: updateErr } = await supabase
        .from("explore_growth_goals")
        .update(applied)
        .eq("id", goal.id)
        .eq("user_id", userId)
        .select()
        .single();
      if (!updateErr && updated) updatedGoal = updated;
    }
  }

  // 4) 目标状态流转（暂停/受阻/完成/归档/恢复）
  if (result.goal_status_update && goal?.id) {
    const su = result.goal_status_update;
    const stages = Array.isArray(goal.stages) ? goal.stages : [];
    if (su.status === "completed") {
      for (const s of stages) (s as Record<string, unknown>).status = "completed";
    } else if (su.status === "active" && stages.length > 0) {
      const hasActive = stages.some((s) => (s as Record<string, unknown>)?.status === "active");
      if (!hasActive) {
        const next = stages.find((s) => (s as Record<string, unknown>)?.status === "not_started");
        if (next) (next as Record<string, unknown>).status = "active";
      }
    }
    const patch: Record<string, unknown> = { status: su.status };
    if (su.status === "completed") patch.progress = 100;
    if (stages.length > 0) patch.stages = stages;
    const { data: updatedStatusGoal, error: statusErr } = await supabase
      .from("explore_growth_goals")
      .update(patch)
      .eq("id", goal.id)
      .eq("user_id", userId)
      .select()
      .single();
    if (!statusErr && updatedStatusGoal) updatedGoal = updatedStatusGoal;
  }

  return {
    reply: result.reply,
    memory: savedMemory,
    goal_update: result.goal_update,
    goal_status_update: result.goal_status_update,
    goal: updatedGoal,
  };
};

type StreamContext = {
  apiKey: string;
  model: string;
  messages: unknown[];
  temperature: number;
  /** 模型输出结束后执行副作用；抛错会被转成 error 事件 */
  onFinish: (result: ModelResult) => Promise<void>;
};

/**
 * 流式出口：模型生成过程中就把 reply 增量推给客户端，
 * 生成结束后再跑副作用，最后发 done 收尾。
 * done 刻意放在副作用之后——客户端收到它才会刷新记忆和目标。
 */
const streamConversation = (ctx: StreamContext): ReadableStream<Uint8Array> => {
  const encoder = new TextEncoder();
  return new ReadableStream({
    async start(controller) {
      const send = (data: unknown) =>
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`));
      const maxAttempts = 3;
      let lastError = "DeepSeek request failed";

      for (let attempt = 0; attempt < maxAttempts; attempt++) {
        const abort = new AbortController();
        // 只约束「拿到响应头」的时间；开始流式输出后不再计时，否则长回复会被中断
        const timer = setTimeout(() => abort.abort(), 15000);
        let started = false;
        try {
          const res = await fetch(DEEPSEEK_URL, {
            method: "POST",
            headers: { "Authorization": `Bearer ${ctx.apiKey}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              model: ctx.model,
              temperature: ctx.temperature,
              stream: true,
              messages: ctx.messages,
            }),
            signal: abort.signal,
          });
          clearTimeout(timer);
          if (!res.ok || !res.body) {
            lastError = `DeepSeek HTTP ${res.status}`;
            if (res.status !== 429 && res.status < 500) break;
            await new Promise((resolve) => setTimeout(resolve, 2000 * Math.pow(2, attempt)));
            continue;
          }

          const reader = res.body.getReader();
          const decoder = new TextDecoder();
          let buffer = "";
          const replyStream = createReplyStream((chunk) => {
            started = true;
            send({ reply: chunk });
          });

          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() ?? "";
            for (const line of lines) {
              const trimmed = line.trim();
              if (!trimmed.startsWith("data:")) continue;
              const payload = trimmed.slice(5).trim();
              if (payload === "[DONE]") continue;
              try {
                const chunk = JSON.parse(payload);
                const delta = chunk?.choices?.[0]?.delta?.content;
                if (typeof delta === "string" && delta) replyStream.feed(delta);
              } catch {
                // 忽略半截或异常帧
              }
            }
          }

          const parsed = parseModelResult(replyStream.raw());
          if (!parsed.reply.trim()) {
            send({ error: "AI 暂时没有回复，请稍后重试。" });
            controller.close();
            return;
          }
          await ctx.onFinish(parsed);
          // done 带上最终回复：模型返回纯文本且较短时增量不会输出，靠这里补全
          send({ done: true, reply: parsed.reply });
          controller.close();
          return;
        } catch (error) {
          clearTimeout(timer);
          lastError = error instanceof Error ? error.message : String(error);
          if (started) {
            // 已经吐过内容就不能重试了，否则前端会看到重复文本
            send({ error: lastError });
            controller.close();
            return;
          }
        }
        if (attempt < maxAttempts - 1) {
          await new Promise((resolve) => setTimeout(resolve, 2000 * Math.pow(2, attempt)));
        }
      }

      send({ error: lastError });
      controller.close();
    },
  });
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const deepseekApiKey = Deno.env.get("DEEPSEEK_API_KEY");
  const deepseekModel = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
  const dashscopeApiKey = Deno.env.get("DASHSCOPE_API_KEY");
  const dashscopeBaseUrl = Deno.env.get("DASHSCOPE_BASE_URL") ?? DASHSCOPE_BASE_URL_DEFAULT;
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
  const sessionId = body?.session_id;
  const mode = body?.mode === "low_mood"
    ? "low_mood"
    : body?.mode === "goal_creation"
      ? "goal_creation"
      : "normal";
  if (typeof sessionId !== "string") return jsonResponse({ error: "session_id is required" }, 400);

  // 这些读取互不依赖，并发发出，减少「开始出字」之前的等待
  const [sessionRes, messagesRes, goalRes, profileRes, recentRes] = await Promise.all([
    supabase
      .from("explore_conversation_sessions")
      .select("id, title, mode, mood_stage")
      .eq("id", sessionId)
      .eq("user_id", userId)
      .single(),
    supabase
      .from("explore_conversations")
      .select("role, content")
      .eq("session_id", sessionId)
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(20),
    supabase
      .from("explore_growth_goals")
      .select("id,title,stages,status,progress")
      .eq("user_id", userId)
      .neq("status", "archived")
      .order("is_main_goal", { ascending: false })
      // 存量数据可能没有 is_main_goal 标志：兜底取最新目标，与 Web 端 loadGoals 排序一致
      .order("created_at", { ascending: false })
      .limit(1),
    supabase
      .from("explore_user_profiles")
      .select("personality,interests,strengths,weaknesses,current_stage,ai_summary")
      .eq("user_id", userId)
      .single(),
    supabase
      .from("explore_memory_items")
      .select("type,content")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(8),
  ]);

  const session = sessionRes.data;
  if (sessionRes.error || !session) return jsonResponse({ error: "Session not found" }, 404);
  if (messagesRes.error) return jsonResponse({ error: messagesRes.error.message }, 500);

  const goal = goalRes.data?.[0];
  const profileRow = profileRes.data;
  const recentRows = recentRes.data;

  const messages = [...(messagesRes.data ?? [])].reverse() as ChatRow[];
  const basePrompt = buildSystemPrompt(mode);
  const moodStage = typeof session.mood_stage === "number" ? Math.min(session.mood_stage, 3) : 0;
  const moodInstruction = mode === "low_mood" ? `\n\n${MOOD_STAGE_INSTRUCTIONS[moodStage]}` : "";

  let goalContext = "";
  if (goal && Array.isArray(goal.stages) && goal.stages.length > 0) {
    const activeStage = (goal.stages as any[]).find((s) => s?.status === "active") ?? (goal.stages as any[])[0];
    goalContext = JSON.stringify({ title: goal.title, status: goal.status, active_stage: activeStage });
  }
  const goalInstruction = goalContext
    ? `\n\n用户当前主目标及阶段如下：${goalContext}\n如果用户在对话中表达了某个行动项已完成、阶段要推进、或目标已完成的信号，请额外返回 goal_update 对象：{"done_actions":["已完成行动项的内容（尽量与行动项原文一致）"],"advance_stage":true或false,"goal_completed":true或false,"note":"一句话说明进度变化"}；若没有进度变化，则不要返回 goal_update。`
    : "";

  let profileContext = "";
  if (profileRow) {
    profileContext = JSON.stringify({
      personality: profileRow.personality,
      interests: profileRow.interests,
      strengths: profileRow.strengths,
      weaknesses: profileRow.weaknesses,
      current_stage: profileRow.current_stage,
      summary: profileRow.ai_summary,
    });
  }

  let recentContext = "";
  if (recentRows?.length) {
    recentContext = recentRows
      .map((m) => `- [${m.type}] ${m.content}`)
      .join("\n");
  }

  let memoryContext = "";
  if (dashscopeApiKey) {
    const lastUser = [...messages].reverse().find((m) => m.role === "user");
    if (lastUser?.content) {
      try {
        const embedRes = await fetch(`${dashscopeBaseUrl}/embeddings`, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${dashscopeApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ model: "text-embedding-v4", input: [lastUser.content], dimensions: 1536 }),
        });
        if (embedRes.ok) {
          const embedData = await embedRes.json();
          const queryEmbedding = embedData?.data?.[0]?.embedding;
          if (Array.isArray(queryEmbedding)) {
            const { data: matched, error: matchError } = await supabase.rpc("explore_match_memories", {
              p_user_id: userId,
              query_embedding: queryEmbedding,
              match_threshold: 0.3,
              match_count: 6,
            });
            if (!matchError && matched?.length) {
              memoryContext = matched
                .map((m: any) => `- [${m.type}] ${m.content}`)
                .join("\n");
            }
          }
        }
      } catch {
        // 召回失败不应阻断对话
      }
    }
  }

  const systemPrompt = [
    basePrompt,
    moodInstruction,
    goalInstruction,
    profileContext
      ? `\n\n你对这位用户的画像理解如下（仅供理解，不要直接复述）：\n${profileContext}`
      : "",
    recentContext
      ? `\n\n用户最近的记忆/事件（仅供理解近况，不要复述原文）：\n${recentContext}`
      : "",
    memoryContext
      ? `\n\n以下是与你当前话题相关的历史记忆（如无必要，不要复述原文）：\n${memoryContext}`
      : "",
  ].join("");

  return sseResponse(
    streamConversation({
      apiKey: deepseekApiKey,
      model: deepseekModel,
      messages: [{ role: "system", content: systemPrompt }, ...messages],
      temperature: 0.7,
      onFinish: (result) =>
        applyTurnSideEffects({
          supabase,
          userId,
          sessionId,
          mode,
          moodStage,
          goal,
          result,
          dashscopeApiKey,
          dashscopeBaseUrl,
        }),
    }),
  );
});
