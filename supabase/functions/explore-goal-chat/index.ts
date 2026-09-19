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

const normalizeGoal = (rawGoal: unknown) => {
  if (
    rawGoal &&
    typeof rawGoal === "object" &&
    typeof (rawGoal as any).title === "string" &&
    (rawGoal as any).title.trim()
  ) {
    return {
      title: (rawGoal as any).title.trim(),
      description: typeof (rawGoal as any).description === "string" ? (rawGoal as any).description.trim() : "",
      success_definition: typeof (rawGoal as any).success_definition === "string" ? (rawGoal as any).success_definition.trim() : "",
    };
  }
  return null;
};

const systemPrompt = `你是“探境”，一个温和、具体、长期理解用户的个人成长 Agent。
当前处于“目标共创”模式：你通过对话帮助用户厘清一个真实的成长方向。
先回应并进一步追问，不要急着下结论；只有当方向已经足够清晰、可以落地时，才把它提炼成一个目标。
请只返回 JSON，不要 Markdown，不要额外解释，格式如下：
{"reply":"给用户的自然回复","goal":null}
当方向已经基本清晰（能提炼出标题和大致成功标准）时，就返回 goal 对象；如果还完全不清楚，goal 才是 null：
{"title":"目标标题","description":"为什么想实现它","success_definition":"可衡量的成功标准"}
如果目标还不够清晰，goal 为 null，继续用追问帮助用户明确。

安全底线（任何模式下都必须遵守）：
- 不做诊断、不给出医疗或心理治疗建议，不使用“抑郁症”“焦虑症”等诊断性说法。
- 不鼓励、不美化自伤、自杀或伤害他人的行为，也不讨论这些行为的具体方式。
- 若用户流露出自伤、自杀或伤害他人的倾向：先明确表达关心，再建议他联系信任的人或专业帮助（当地心理援助热线、急救电话），不要停留在情绪分析或继续追问上。
- 涉及人身安全的紧急情况，直接建议拨打当地紧急电话。`;

type GoalChatResult = {
  reply: string;
  goal: ReturnType<typeof normalizeGoal>;
  error?: string;
};

// 调用 DeepSeek 流式接口，边接收边通过 onReply 回调吐出 reply 增量。
// 不传 onReply 时就是一次普通的非流式调用，只返回完整结果。
const runGoalChat = async (
  apiKey: string,
  model: string,
  messages: unknown[],
  onReply?: (chunk: string) => void,
): Promise<GoalChatResult> => {
  const emit = (chunk: string) => onReply?.(chunk);
  const maxAttempts = 3;
  let lastError = "DeepSeek request failed";

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 15000);
    try {
      const res = await fetch(DEEPSEEK_URL, {
        method: "POST",
        headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model,
          temperature: 0.6,
          stream: true,
          messages,
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
      let raw = "";
      let state: "idle" | "inReply" | "done" = "idle";
      let i = 0;
      let pendingReply = "";
      let escaped = false;
      let mode: "undecided" | "json" | "plain" = "undecided";
      let plainSent = 0;
      let fullReply = "";

      const flushReply = () => {
        if (pendingReply) {
          fullReply += pendingReply;
          emit(pendingReply);
          pendingReply = "";
        }
      };

      const feed = (delta: string) => {
        raw += delta;
        if (mode === "plain") {
          if (raw.length > plainSent) {
            const chunk = raw.slice(plainSent);
            fullReply += chunk;
            emit(chunk);
            plainSent = raw.length;
          }
          return;
        }
        if (mode === "undecided") {
          if (raw.trimStart().startsWith("{")) {
            mode = "json";
          } else if (raw.indexOf('"reply"') >= 0) {
            mode = "json";
          } else if (raw.length > 60) {
            mode = "plain";
            fullReply += raw;
            emit(raw);
            plainSent = raw.length;
            return;
          } else {
            return;
          }
        }
        if (state === "done") return;
        if (state === "idle") {
          const keyIdx = raw.indexOf('"reply"');
          if (keyIdx < 0) return;
          let p = keyIdx + 7;
          while (p < raw.length && (raw[p] === " " || raw[p] === "\t")) p++;
          if (p >= raw.length || raw[p] !== ":") return;
          p++;
          while (p < raw.length && (raw[p] === " " || raw[p] === "\t")) p++;
          if (p >= raw.length || raw[p] !== '"') return;
          state = "inReply";
          i = p + 1;
        }
        while (i < raw.length) {
          const ch = raw[i];
          if (escaped) {
            if (ch === "u" && i + 4 < raw.length) {
              const hex = raw.slice(i + 1, i + 5);
              if (/^[0-9a-fA-F]{4}$/.test(hex)) {
                pendingReply += String.fromCharCode(parseInt(hex, 16));
                i += 5;
              } else {
                pendingReply += "u";
                i++;
              }
            } else {
              const map: Record<string, string> = {
                n: "\n",
                t: "\t",
                r: "\r",
                '"': '"',
                "\\": "\\",
                "/": "/",
              };
              pendingReply += map[ch] ?? ch;
              i++;
            }
            escaped = false;
            continue;
          }
          if (ch === "\\") {
            escaped = true;
            i++;
            continue;
          }
          if (ch === '"') {
            state = "done";
            i++;
            break;
          }
          pendingReply += ch;
          i++;
        }
        flushReply();
      };

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
            if (typeof delta === "string" && delta) feed(delta);
          } catch {
            // ignore partial or malformed frames
          }
        }
      }

      const parsed = extractJson(raw);
      if (!fullReply.trim()) {
        return { reply: "", goal: null, error: "AI 暂时没有回复，请稍后重试。" };
      }
      return { reply: fullReply, goal: normalizeGoal(parsed?.goal) };
    } catch (error) {
      clearTimeout(timer);
      lastError = error instanceof Error ? error.message : String(error);
    }
    if (attempt < maxAttempts - 1) {
      await new Promise((resolve) => setTimeout(resolve, 2000 * Math.pow(2, attempt)));
    }
  }

  return { reply: "", goal: null, error: lastError };
};

const streamGoalChat = (
  apiKey: string,
  model: string,
  messages: unknown[],
): ReadableStream<Uint8Array> => {
  const encoder = new TextEncoder();
  return new ReadableStream({
    async start(controller) {
      const send = (data: unknown) =>
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`));
      const result = await runGoalChat(apiKey, model, messages, (chunk) => send({ reply: chunk }));
      if (result.error) send({ error: result.error });
      else send({ goal: result.goal });
      controller.close();
    },
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

    const body = await request.json().catch(() => null);
    const messages = Array.isArray(body?.messages) ? body.messages : [];
    const clean = messages
      .filter((m: any) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
      .map((m: any) => ({ role: m.role, content: m.content }))
      .slice(-20);
    if (clean.length === 0) return jsonResponse({ error: "messages is required" }, 400);

    const chatMessages = [{ role: "system", content: systemPrompt }, ...clean];

    // 客户端显式请求 text/event-stream 才走流式；否则返回与移动端 invoke 兼容的 JSON。
    const wantsStream = (request.headers.get("Accept") ?? "").includes("text/event-stream");
    if (!wantsStream) {
      const result = await runGoalChat(deepseekApiKey, deepseekModel, chatMessages);
      if (result.error) return jsonResponse({ error: result.error }, 502);
      return jsonResponse({ reply: result.reply, goal: result.goal });
    }

    return sseResponse(streamGoalChat(deepseekApiKey, deepseekModel, chatMessages));
  } catch (err) {
    return jsonResponse({
      error: err instanceof Error ? err.message : String(err),
    }, 500);
  }
});
